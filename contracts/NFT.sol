//SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/interfaces/IERC2981.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @title NFT
 * @notice Implementation of [ERC721Upgradeable] including Enumerable extension
 * @dev IERC2981 - Interface for the NFT Royalty Standard.
 */
contract NFT is Initializable, UUPSUpgradeable, ERC721EnumerableUpgradeable, IERC2981, OwnableUpgradeable {
    using Counters for Counters.Counter;
    using Strings for uint256;
    using SafeMath for uint256;

    /// @notice Counter to keep track of the number of NFTs minted
    Counters.Counter private _tokenIds;
    /// @notice The URI to the contract meta data.
    string private _contractURI;
    /// @notice Base URI for computing {tokenURI}.
    string private baseURI;
    /// @notice Base extension for computing {tokenURI}.
    string public baseExtension;

    /// @notice Mapping from token ID to creators address
    mapping(uint256 => address) public creators;
    /// @notice Mapping from token ID to token URI
    mapping(uint256 => string) public tokenUri;

    /// @notice structure for Royalty Information
    struct RoyaltyInfo {
        address recipient;
        uint256 amount;
    }

    /// @notice Mapping from token ID to royalty information
    mapping(uint256 => RoyaltyInfo) private _royalties;

    /// @dev This event MUST be emitted by `onRoyaltiesReceived()`.
    event RoyaltiesReceived(
        address indexed _royaltyRecipient,
        address indexed _buyer,
        uint256 indexed _tokenId,
        address _tokenPaid,
        uint256 _amount,
        bytes32 _metadata
    );

    /**
     * @dev Initializes the contract
     * @param _name setting a `name` to the token collection.
     * @param _symbol setting a `symbol` to the token collection.
     * @param _contractUri setting the URI to the contract metadata
     */
    function initialize(
        string memory _name,
        string memory _symbol,
        string memory _contractUri
    ) public initializer {
        __ERC721_init(_name, _symbol);
        __Ownable_init();
        baseExtension = ".json";
        _contractURI = _contractUri;
    }

    ///@dev function that should revert when `msg.sender` is not authorized to upgrade the contract.
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
 
    /**
     * @notice function that mint NFT with URI and Royalty
     * @param uri that we want to assign to NFT
     * @param royaltyValue that we want to assign to NFT
     * @return an id of created NFT
     */
    function mint(string memory uri, uint256 royaltyValue)
        public
        returns (uint256)
    {
        _tokenIds.increment();
        uint256 newItemId = _tokenIds.current();

        creators[newItemId] = msg.sender;
        tokenUri[newItemId] = uri;

        _mint(msg.sender, newItemId);

        if (royaltyValue > 0) {
            _setTokenRoyalty(newItemId, msg.sender, royaltyValue);
        }

        return newItemId;
    }

    /**
     * @notice A distinct Uniform Resource Identifier (URI) for a given asset.
     * @dev Throws if `tokenId` is not exist
     * @param tokenId the NFT identifier
     * @return The Uniform Resource Identifier (URI) for `tokenId` token
     */
    function tokenURI(uint256 tokenId)
        public
        view
        override
        returns (string memory)
    {
        require(_exists(tokenId), "URI query for nonexistent token");

        string memory _tokenURI = tokenUri[tokenId];

        if (bytes(baseURI).length == 0) {
            return _tokenURI;
        } else {
            return
                string(
                    abi.encodePacked(baseURI, tokenId.toString(), baseExtension)
                );
        }
    }

    /**
     * @notice Set base extension for token metadata
     * @dev Caller must be contract owner
     * @param newBaseExtension the new extension to set
     */
    function setBaseExtension(string memory newBaseExtension) public onlyOwner {
        baseExtension = newBaseExtension;
    }

    /**
     * @notice Expose the contractURI
     * @return the contract metadata URI.
     */
    function contractURI() public view returns (string memory) {
        return _contractURI;
    }

    /**
     * @notice Set the contract metadata URI
     * @dev Caller must be contract owner
     * @param contractURI_ the URI to set
     */
    function setContractURI(string memory contractURI_) public onlyOwner {
        _contractURI = contractURI_;
    }

    /**
     * @notice Expose the baseURI
     * @dev Base URI for computing {tokenURI}.
     * @return the base URI
     */
    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    /**
     * @notice Set base URI for token metadata
     * @dev Caller must be contract owner
     * @param baseURI_ the URI to set
     */
    function setBaseURI(string memory baseURI_) public onlyOwner {
        baseURI = baseURI_;
    }

    /**
     * @notice Lists all the NFTs owned by `_owner`
     * @param _owner The address to consult
     * @return A list of NFT IDs belonging to `_owner`
     */
    function tokensOfOwner(address _owner)
        external
        view
        returns (uint256[] memory)
    {
        uint256 tokenCount = balanceOf(_owner);
        uint256[] memory tokensId = new uint256[](tokenCount);

        for (uint256 i = 0; i < tokenCount; i++) {
            tokensId[i] = tokenOfOwnerByIndex(_owner, i);
        }

        return tokensId;
    }

    /**
     * @notice Update royalty info for a token
     * @dev Update the `recipient` royalty with the royalty `value` for `tokenId` token
     * @param tokenId the token id that we register the royalties for
     * @param recipient recipient of the royalties
     * @param value percentage (using 2 decimals: 10000 = 100)
     */
    function _setTokenRoyalty(
        uint256 tokenId,
        address recipient,
        uint256 value
    ) internal {
        require(value <= 10000, "ERC2981Royalties: Too high");
        _royalties[tokenId] = RoyaltyInfo(recipient, uint24(value));
    }

    /**
     * @notice Query if a contract implements an interface
     * @dev This function uses less than 30,000 gas.
     * @param interfaceId is the interface Identifier
     * @return true if this contract implements the interfaceId
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721EnumerableUpgradeable, IERC165)
        returns (bool)
    {
        return
            interfaceId == type(IERC2981).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /**
     * @notice Called to return both the creator's address and the royalty percentage
     * @param tokenId - the NFT asset queried for royalty information
     * @param value - the sale price of the NFT asset specified by _tokenId
     * @return receiver - address of who should be sent the royalty payment
     * @return royaltyAmount - the royalty payment amount for _salePrice
     */
    function royaltyInfo(uint256 tokenId, uint256 value)
        external
        view
        override
        returns (address receiver, uint256 royaltyAmount)
    {
        RoyaltyInfo memory royalties = _royalties[tokenId];
        receiver = royalties.recipient;
        royaltyAmount = (value * royalties.amount) / 10000;
    }

    /**
     * @notice Called when royalty is transferred to the receiver
     * @param _royaltyRecipient The address of who is entitled to the royalties
     * @param _buyer If known, the address buying the NFT on a secondary sale
     * @param _tokenId the ID of the ERC-721 token that was sold
     * @param _tokenPaid The address of the token used to pay the royalty fee amount
     * @param _amount The amount being paid to the creator
     * @param _metadata Arbitrary data attached to this payment
     * @return `bytes4(keccak256("onRoyaltiesReceived(address,address,uint256,address,uint256,bytes32)"))`
     */
    function onRoyaltiesReceived(
        address _royaltyRecipient,
        address _buyer,
        uint256 _tokenId,
        address _tokenPaid,
        uint256 _amount,
        bytes32 _metadata
    ) external returns (bytes4) {
        emit RoyaltiesReceived(
            _royaltyRecipient,
            _buyer,
            _tokenId,
            _tokenPaid,
            _amount,
            _metadata
        );
        return
            bytes4(
                keccak256(
                    "onRoyaltiesReceived(address,address,uint256,address,uint256,bytes32)"
                )
            );
    }
}
