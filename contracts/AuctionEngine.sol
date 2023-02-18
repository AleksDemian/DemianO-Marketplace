//SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/interfaces/IERC2981.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import "./IFeeProvider.sol";

/**
 * @title AuctionEngine
 * @notice Will contains all the business logic sale and purchase of tokens on auctions.
 * @dev uses ReentrancyGuard for security
 */
contract AuctionEngine is Initializable, UUPSUpgradeable, ReentrancyGuardUpgradeable, OwnableUpgradeable, IERC721Receiver {
    using AddressUpgradeable for address;
    using ERC165Checker for address;

    /// @notice fee destination contract address
    address payable public feeDestination;
    /// @notice token contract address
    address public token;
    /// @notice marketplace contract address
    address public marketplace;
    /// @notice platform fee for Coin in percentage (using 2 decimals: 10000 = 100)
    uint256 public platformFeeInCoin;
    /// @notice platform fee for Token in percentage (using 2 decimals: 10000 = 100)
    uint256 public platformFeeInToken;
    /// @notice admin address
    address public admin;
    /// @notice array with all auctions
    Auction[] public auctions;

    /// @notice status type for auctions
    enum Status { pending, active, finished }

    /// @notice structure for auction information
    struct Auction {
        address nftContract;
        uint256 tokenId;
        address currency;
        address creator;
        uint256 startTime;
        uint256 duration;
        uint256 currentBidAmount;
        address currentBidOwner;
        uint256 bidCount;
        bool finalized;
    }

    /**
     * @dev initializes the contract
     * @param _token ERC20 token contract address
     * @param _marketplace marketplace contract address
     * @param _feeDestination fee destination contract address
     */
    function initialize(
        address _token, 
        address _marketplace, 
        address payable _feeDestination
    ) public initializer {
        token = _token;
        marketplace = _marketplace;
        feeDestination = _feeDestination;
        admin = msg.sender;
        __Ownable_init();
        __ReentrancyGuard_init();
    }

    ///@dev function that should revert when `msg.sender` is not authorized to upgrade the contract.
    function _authorizeUpgrade(address newImplementation) internal override onlyAdmin {}
 
    /**
     * @notice creates an auction with the given informatin
     * @dev lock NFT on auction contract
     * @param _nftContract ERC721 contract address
     * @param _tokenId the NFT identifier
     * @param _startPrice set auction start price
     * @param _startTime set start time
     * @param _duration set duration in seconds
     * @param _currency set auction currency address
     */
    function createAuction(
        address _nftContract,
        uint256 _tokenId,
        uint256 _startPrice,
        uint256 _startTime,
        uint256 _duration,
        address _currency
    ) public onlyNonContracts nonReentrant {
        IERC721 asset = IERC721(_nftContract);
        require(asset.ownerOf(_tokenId) == msg.sender, "Only token owner can do this");

        if (_startTime == 0) { _startTime = block.timestamp; }

        Auction memory auction = Auction({
            creator: msg.sender,
            nftContract: _nftContract,
            tokenId: _tokenId,
            currency: _currency,
            startTime: _startTime,
            duration: _duration,
            currentBidAmount: _startPrice,
            currentBidOwner: address(0),
            bidCount: 0,
            finalized: false
        });

        auctions.push(auction);
        uint256 index = auctions.length - 1;

        IERC721(_nftContract).safeTransferFrom(msg.sender, address(this), _tokenId);        

        emit NewAuction(index, auction.creator, auction.nftContract, auction.tokenId, auction.currentBidAmount, auction.startTime, auction.duration, auction.currency);
    }

    /**
     * @notice remove token from auction
     * @dev caller must be auction owner. Unlock NFT from the auction
     * @param auctionIndex the auction identifier
     */
    function cancelAuction(uint256 auctionIndex) public {
        Auction storage auction = auctions[auctionIndex];
        require(auction.creator == msg.sender, "Only auction owner");
        require(auction.currentBidOwner == address(0), "Auction has a bid");
        
        auction.finalized = true;

        IERC721(auction.nftContract).safeTransferFrom(address(this), msg.sender , auction.tokenId);       

        emit AuctionCanceled(auction.nftContract, auction.tokenId, auctionIndex);
    }

    /**
     * @dev bidder sends bid on an auction
     * @dev auction should be active and not ended
     * @dev refund previous bidder if a new bid is valid and placed.
     * @param auctionIndex the auction identifier
     * @param amount number of tokens per bid
     */
    function bid(uint256 auctionIndex, uint256 amount) public payable onlyNonContracts nonReentrant {
        Auction storage auction = auctions[auctionIndex];
        require(isActive(auctionIndex), "Auction must be active");


        if (auction.currentBidOwner == address(0)) {
            require(amount >= auction.currentBidAmount, "You bid less then price");
        } else {
            require(amount > auction.currentBidAmount, "You don't outbid");
        }
            // we got a better bid. Return tokens to the previous best bidder
            // and register the sender as `currentBidOwner`

            if (auction.currency == address(0)){
                require(msg.value == amount, "Submit the asking price");

                if (auction.currentBidOwner != address(0)) {
                    // return funds to the previuos bidder
                    payable(auction.currentBidOwner).transfer(auction.currentBidAmount);
                }
            } else {     
                require(IERC20(auction.currency).transferFrom(msg.sender, address(this), amount), "Submit the asking price in ECR20");
            
                if (auction.currentBidOwner != address(0)) {
                    // return funds to the previuos bidder
                    IERC20(auction.currency).transfer(
                        auction.currentBidOwner,
                        auction.currentBidAmount
                    );
                }
            }

            // register new bidder
            auction.currentBidAmount = amount;
            auction.currentBidOwner = msg.sender;
            auction.bidCount++;

            emit NewBid(auction.nftContract, auction.tokenId, auctionIndex, msg.sender, amount);
    }

    /**
     * @dev gets the length of auctions
     * @return uint256 representing the auction count
     */
    function getTotalAuctions() public view returns (uint256) { return auctions.length; }

    /**
     * @dev get the active status of auction
     * @param auctionIndex the auction identifier
     * @return boolean representing the auction status
     */
    function isActive(uint256 auctionIndex) public view returns (bool) { return getStatus(auctionIndex) == Status.active; }

    /**
     * @dev get the finished status of auction
     * @param auctionIndex the auction identifier
     * @return boolean representing the auction status
     */
    function isFinished(uint256 auctionIndex) public view returns (bool) { return getStatus(auctionIndex) == Status.finished; }
 
    /**
     * @dev get the status of auction
     * @param auctionIndex the auction identifier
     * @return status type of the auction
     */
    function getStatus(uint256 auctionIndex) public view returns (Status) {
        Auction storage auction = auctions[auctionIndex];
        if (block.timestamp < auction.startTime) {
            return Status.pending;
        } else if (block.timestamp < auction.startTime + auction.duration) {
            return Status.active;
        } else {
            return Status.finished;
        }
    }

    /**
     * @dev get current bid owner of auction
     * @param auctionIndex the auction identifier
     */
    function getCurrentBidOwner(uint256 auctionIndex) public view returns (address) { return auctions[auctionIndex].currentBidOwner; }
  
    /**
     * @dev get current bid amount of auction
     * @param auctionIndex the auction identifier
     */
    function getCurrentBidAmount(uint256 auctionIndex) public view returns (uint256) { return auctions[auctionIndex].currentBidAmount; }

    /**
     * @dev get current bid count of auction
     * @param auctionIndex the auction identifier
     */
    function getBidCount(uint256 auctionIndex) public view returns (uint256) { return auctions[auctionIndex].bidCount; }

    /**
     * @dev get winner of auction
     * @param auctionIndex the auction identifier
     */
    function getWinner(uint256 auctionIndex) public view returns (address) {
        require(isFinished(auctionIndex), "Auction must be finished");
        return auctions[auctionIndex].currentBidOwner;
    }

    /**
     * @notice update fee destination
     * @dev caller must be contract owner
     * @param _feeDestination fee destination contract address
     */
    function updateFeeDestination(address payable _feeDestination) public onlyOwner { feeDestination = _feeDestination; }
    
    /**
     * @notice update marketplace address
     * @dev caller must be contract owner
     * @param _marketplace marketplace contract address
     */
    function updateMarketplace(address _marketplace) public onlyOwner { marketplace = _marketplace; }

    /**
     * @notice update admin address
     * @dev caller must be admin
     * @param _admin admin contract address
     */
    function updateAdmin(address _admin) public onlyAdmin { admin = _admin; }
 
    /**
     * @notice update token address
     * @dev caller must be admin
     * @param _token admin contract address
     */
    function updateToken(address _token) public onlyOwner { token = _token; }
  
    /**
     * @dev finalized an ended auction
     * @dev the auction should be ended
     * @dev on success asset is transfered to bidder and auction owner gets the amount
     * @param auctionIndex uint256 ID of the created auction
     */
    function finalize(uint256 auctionIndex) public nonReentrant{
        require(isFinished(auctionIndex), "Auction must be finished");
        Auction storage auction = auctions[auctionIndex];
        require(auction.currentBidOwner != address(0), "Auction have no bid");
        require(auction.finalized == false, "Auction can be finalized only once");
        address winner = getWinner(auctionIndex);
        
        uint256 platformFeeAmount;
        address royaltyReceiver;
        uint256 royaltyAmount;

        if (auction.nftContract.supportsInterface(type(IERC2981).interfaceId)) {
            (royaltyReceiver, royaltyAmount) = IERC2981(auction.nftContract)
                .royaltyInfo(auction.tokenId, auction.currentBidAmount);
        }

        auction.finalized = true;
            
        if (auction.currency == address(0)) {
            
            uint256 platformFee = IFeeProvider(marketplace).platformFeeInCoin();

            platformFeeAmount = (auction.currentBidAmount * platformFee) / 10000;

            if (royaltyAmount != 0 && royaltyReceiver != auction.creator) {
                if(royaltyAmount == auction.currentBidAmount) {
                    royaltyAmount = royaltyAmount - platformFeeAmount;
                }
                payable(royaltyReceiver).transfer(royaltyAmount);
            } else {
                royaltyAmount = 0;
            }

            if (platformFee != 0) {
                feeDestination.transfer(platformFeeAmount);
            }

            if(auction.currentBidAmount > platformFeeAmount + royaltyAmount) {
                payable(auction.creator).transfer(
                    auction.currentBidAmount - platformFeeAmount - royaltyAmount
                );
            }
        } else { 
            uint256 platformFee;
            if (auction.currency == token) {
                platformFee = IFeeProvider(marketplace).platformFeeInToken();
            } else {
                platformFee = IFeeProvider(marketplace).platformFeeInCoin();
            }

            platformFeeAmount = (auction.currentBidAmount * platformFee) / 10000;

            if (royaltyAmount != 0 && royaltyReceiver != auction.creator) {
                if(royaltyAmount == auction.currentBidAmount) {
                    royaltyAmount = royaltyAmount - platformFeeAmount;
                }
                IERC20(auction.currency).transfer(
                    royaltyReceiver,
                    royaltyAmount
                );
            }  else {
                royaltyAmount = 0;
            }

            if (platformFee != 0) {
                IERC20(auction.currency).transfer(
                    feeDestination,
                    platformFeeAmount
                );
            }

            if(auction.currentBidAmount > platformFeeAmount + royaltyAmount) {
                IERC20(auction.currency).transfer(
                    auction.creator,
                    auction.currentBidAmount - platformFeeAmount - royaltyAmount
                );
            }
        }

        IERC721(auction.nftContract).safeTransferFrom(address(this), winner, auction.tokenId);

        emit AuctionFinalized(auction.nftContract, auction.tokenId, winner, auctionIndex, auction.currency, auction.currentBidAmount, platformFeeAmount, royaltyAmount);
    }

    /**
     * @dev Whenever an {IERC721} `tokenId` token is transferred to this
     * contract via {IERC721-safeTransferFrom} by `operator` from `from`,
     * this function is called
     * @return its Solidity selector to confirm the token transfer.
     */
    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) public virtual override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    /**
     * @notice It allows the admins to get tokens sent to the contract
     * @param tokenAddress: the address of the token to withdraw
     * @param tokenAmount: the number of token amount to withdraw
     * @dev Only callable by owner
     */
    function recoverTokens(address tokenAddress, uint256 tokenAmount)
        external
        onlyOwner
    {
        require(tokenAddress != address(0), "Address can not be zero!");
        IERC20(tokenAddress).transfer(address(msg.sender), tokenAmount);
    }

    /**
     * @notice It allows the admins to get collected coins
     * @param amount: amount to withdraw
     * @dev Only callable by owner
     */
    function withdraw(uint256 amount) external onlyOwner {
        require(
            payable(msg.sender).send(amount),
            "Cannot withdraw"
        );
    }

    /**
     * @notice it allows the admins to get NFT sent to the contract, if there will be any issue with contract
     * @param auctionIndex: auctionIndex to recover token from auction
     * @dev Only callable by owner
     */
    function recoverAsset(uint256 auctionIndex)
        external
        onlyOwner
    {
        Auction storage auction = auctions[auctionIndex];
        require(!auction.finalized, "Not allowed");
        
        IERC721(auction.nftContract).safeTransferFrom(
            address(this),
            auction.creator,
            auction.tokenId
        );
    }

    //---------------Modifiers--------------//

    /// @dev Allows only for Externally-owned accounts (EOAs)
    modifier onlyNonContracts() {
        require(!msg.sender.isContract(), "Only non contracts account");
        _;
    }
    
    /// @dev Allows only admin
    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin");
        _;
    }

    //---------------Events-----------------//

    event NewAuction(
        uint256 auctionIndex,
        address indexed creator, 
        address indexed asset,
        uint256 indexed tokenId, 
        uint256 price, 
        uint256 startTime, 
        uint256 duration, 
        address currency
    );
    event AuctionCanceled(
        address indexed asset,
        uint256 indexed tokenId, 
        uint256 indexed auctionIndex
    );
    event NewBid(
        address indexed asset,
        uint256 indexed tokenId, 
        uint256 indexed auctionIndex, 
        address bidder,
        uint256 amount
    );
    event AuctionFinalized(
        address indexed asset,
        uint256 indexed tokenId,
        address indexed buyer,
        uint256 auctionIndex,
        address currency, 
        uint256 price,
        uint256 fee,
        uint256 royalty
    );
}