//SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin/contracts/interfaces/IERC2981.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @title Marketplace
 * @notice Will contains all the business logic sale and purchase of tokens.
 * @dev uses ReentrancyGuard for security
 */
contract Marketplace is Initializable, UUPSUpgradeable, ReentrancyGuardUpgradeable, OwnableUpgradeable, IERC721Receiver {
    using AddressUpgradeable for address;
    using ERC165Checker for address;

    /// @notice ERC721 contract address
    address public nftContract;
    /// @notice token contract address
    address public token;
    /// @notice platform fee for Coin in percentage (using 2 decimals: 10000 = 100)
    uint256 public platformFeeInCoin;
    /// @notice platform fee for Token in percentage (using 2 decimals: 10000 = 100)
    uint256 public platformFeeInToken;

    /// @notice fee destination contract address
    address payable public feeDestination;

    /// @notice structure for market item information
    struct MarketItem {
        uint256 price;
        address currency;
        bool forSale;
    }

    /// @notice Mapping from token ID to Market Item
    mapping(uint256 => MarketItem) public idToMarketItem;
    /// @notice Mapping from token ID to token owner address
    mapping(uint256 => address) public tokenOwner;
    /// @notice Mapping from ERC20 address to approved tokens
    mapping(address => bool) public approvedTokens;

    event CoinFeeChanged(
        address indexed account,
        uint256 newFee,
        uint256 oldFee
    );
    event TokenFeeChanged(
        address indexed account,
        uint256 newFee,
        uint256 oldFee
    );
    event TokenOnSale(
        address indexed owner,
        uint256 indexed tokenId,
        uint256 price,
        address currency
    );
    event SalePriceChanged(uint256 indexed tokenId, uint256 price);
    event TokenNotOnSale(uint256 indexed tokenId);
    event TokenBought(
        uint256 indexed tokenId,
        address indexed buyer,
        address currency,
        uint256 price,
        uint256 fee,
        uint256 royalty
    );

    /// @dev Allows only tokens that belong to the owner
    modifier onlyTokenOwner(uint256 tokenId) {
        require(
            tokenOwner[tokenId] == msg.sender,
            "Only token owner can do this"
        );
        _;
    }

    /// @dev Allows only for Externally-owned accounts (EOAs)
    modifier onlyNonContracts() {
        require(!msg.sender.isContract(), "only non contracts account");
        _;
    }

    /**
     * @dev Initializes the contract
     * @param _nft ERC721 contract address
     * @param _token allowed token contract address
     * @param _feeDestination fee destination contract address
     * @param _feeCoin initial platform fee in Coin
     * @param _feeToken initial platform fee in Token
     */
    function initialize(
        address _nft,
        address _token,
        address payable _feeDestination,
        uint256 _feeCoin,
        uint256 _feeToken
    ) public initializer {
        nftContract = _nft;
        token = _token;
        approvedTokens[_token] = true;
        approvedTokens[address(0)] = true;
        feeDestination = _feeDestination;
        platformFeeInCoin = _feeCoin;
        platformFeeInToken = _feeToken;
        __Ownable_init();
        __ReentrancyGuard_init();
    }

    ///@dev function that should revert when `msg.sender` is not authorized to upgrade the contract.
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
 
    /**
     * @notice update new asset address
     * @dev Caller must be contract owner
     * @param nft ERC721 contract address
     */
    function updateAssetAddress(address nft) public onlyOwner {
        nftContract = nft;
    }

    /**
     * @notice update platform fee
     * @dev Caller must be contract owner
     * @param feeToken platform fee for Token in percentage (using 2 decimals: 10000 = 100)
     * @param feeCoin platform fee for Coin in percentage (using 2 decimals: 10000 = 100)
     */
    function updateFee(uint256 feeToken, uint256 feeCoin) public onlyOwner {
        uint256 oldTokenFee = platformFeeInToken;
        uint256 oldCoinFee = platformFeeInCoin;
        if (feeToken != oldTokenFee) {
            platformFeeInToken = feeToken;
            emit TokenFeeChanged(msg.sender, feeToken, oldTokenFee);
        }
        if (feeCoin != oldCoinFee) {
            platformFeeInCoin = feeCoin;
            emit CoinFeeChanged(msg.sender, feeCoin, oldCoinFee);
        }
    }

    /**
     * @notice update fee destination
     * @dev Caller must be contract owner
     * @param _feeDestination fee destination contract address
     */
    function updateFeeDestination(address payable _feeDestination)
        public
        onlyOwner
    {
        feeDestination = _feeDestination;
    }
 
    /**
     * @notice update token address
     * @dev caller must be admin
     * @param _token admin contract address
     */
    function updateToken(address _token) 
        public 
        onlyOwner 
    { 
        token = _token; 
    }
  
    /**
     * @notice Adds an approved contract
     * @param _contractAddress the address of the contract to be added
     */
    function addApprovedToken(address _contractAddress) external onlyOwner {
        approvedTokens[_contractAddress] = true;
    }

    /**
     * @notice Delete an approved contract
     * @param _contractAddress the address of the contract to be deleted
     */
    function deleteApprovedToken(address _contractAddress) external onlyOwner {
        delete approvedTokens[_contractAddress];
    }

    /**
     * @notice put NFT for sale
     * @dev lock NFT on marketplace contract
     * @param tokenId the NFT identifier
     * @param price set NFT price
     * @param currency set NFT currency address
     */
    function putTokenForSale(
        uint256 tokenId,
        uint256 price,
        address currency
    ) public nonReentrant {
        require(price > 0, "Price must be at least 1 wei");
        require(approvedTokens[currency] == true, "Currency must be approved");

        idToMarketItem[tokenId] = MarketItem(price, currency, true);
        tokenOwner[tokenId] = msg.sender;

        IERC721(nftContract).safeTransferFrom(
            msg.sender,
            address(this),
            tokenId
        );

        emit TokenOnSale(msg.sender, tokenId, price, currency);
    }

    /**
     * @notice update token price
     * @dev caller must be token owner
     * @param tokenId the NFT identifier
     * @param _price set new price
     */
    function updateTokenPrice(uint256 tokenId, uint256 _price)
        public
        onlyTokenOwner(tokenId)
    {
        MarketItem storage item = idToMarketItem[tokenId];
        item.price = _price;
        emit SalePriceChanged(tokenId, _price);
    }

    /**
     * @notice remove token from sale
     * @dev caller must be token owner. Unlock NFT from the marketplace
     * @param tokenId the NFT identifier
     */
    function removeTokenFromSale(uint256 tokenId)
        public
        onlyTokenOwner(tokenId)
    {
        MarketItem storage item = idToMarketItem[tokenId];
        item.forSale = false;

        IERC721(nftContract).safeTransferFrom(
            address(this),
            msg.sender,
            tokenId
        );

        delete tokenOwner[tokenId];

        emit TokenNotOnSale(tokenId);
    }

    /**
     * @notice function to buy token
     * @dev can buy for allowed ERC20 or native currency. Send fee and royalty
     * @param tokenId the NFT identifier
     */
    function buyToken(uint256 tokenId)
        public
        payable
        nonReentrant
        onlyNonContracts
    {
        MarketItem storage item = idToMarketItem[tokenId];

        require(item.forSale == true, "Token must be on Sale");

        uint256 platformFeeAmount = 0;
        address royaltyReceiver = address(0);
        uint256 royaltyAmount = 0;

        if (nftContract.supportsInterface(type(IERC2981).interfaceId)) {
            (royaltyReceiver, royaltyAmount) = IERC2981(nftContract)
                .royaltyInfo(tokenId, item.price);
        }

        if (item.currency == address(0)) {
            require(msg.value == item.price, "Submit the asking price");

            platformFeeAmount = (item.price * platformFeeInCoin) / 10000;

            if (royaltyAmount != 0 && royaltyReceiver != tokenOwner[tokenId]) {
                if(royaltyAmount == item.price) {
                    royaltyAmount = royaltyAmount - platformFeeAmount;
                }
                payable(royaltyReceiver).transfer(royaltyAmount);
            } else {
                royaltyAmount = 0;
            }

            if (platformFeeInCoin != 0) {
                feeDestination.transfer(platformFeeAmount);
            }

            if(item.price > platformFeeAmount + royaltyAmount) {
                payable(tokenOwner[tokenId]).transfer(
                    msg.value - platformFeeAmount - royaltyAmount
                );
            }
        } else {
            uint256 platformFee;
            
            if (item.currency == token) {
                platformFee = platformFeeInToken;
            } else {
                platformFee = platformFeeInCoin;
            }

            platformFeeAmount = (item.price * platformFee) / 10000;

            IERC20(item.currency).transferFrom(
                msg.sender,
                address(this),
                item.price
            );

            if (royaltyAmount != 0 && royaltyReceiver != tokenOwner[tokenId]) {
                if(royaltyAmount == item.price) {
                    royaltyAmount = royaltyAmount - platformFeeAmount;
                }
                IERC20(item.currency).transfer(
                    royaltyReceiver,
                    royaltyAmount
                );
            }  else {
                royaltyAmount = 0;
            }

            if (platformFee != 0) {
                IERC20(item.currency).transfer(
                    feeDestination,
                    platformFeeAmount
                );
            }

            if(item.price > platformFeeAmount + royaltyAmount) {
                IERC20(item.currency).transfer(
                    tokenOwner[tokenId],
                    item.price - platformFeeAmount - royaltyAmount
                );
            }
        }

        IERC721(nftContract).safeTransferFrom(
            address(this),
            msg.sender,
            tokenId
        );

        delete tokenOwner[tokenId];
        item.forSale = false;

        emit TokenBought(
            tokenId,
            msg.sender,
            item.currency,
            item.price,
            platformFeeAmount,
            royaltyAmount
        );
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
        require(tokenAddress != address(0), "address can not be zero!");
        IERC20(tokenAddress).transfer(address(msg.sender), tokenAmount);
    }

    /**
     * @notice It allows the admins to get collected coins
     * @dev Only callable by owner
     */
    function withdraw() external onlyOwner {
        require(
            payable(msg.sender).send(address(this).balance),
            "cannot withdraw"
        );
    }

    /**
     * @notice It allows the admins to get NFT sent to the contract, if there will be any issue with contract
     * @param tokenAddress: the address of the token to withdraw
     * @param tokenId: tokenId to withdraw
     * @dev Only callable by owner
     */
    function recoverAsset(address tokenAddress, uint256 tokenId)
        external
        onlyOwner
    {
        require(tokenAddress != address(0), "address can not be zero!");
        IERC721(tokenAddress).safeTransferFrom(
            address(this),
            tokenOwner[tokenId],
            tokenId
        );
    }
}
