const { expect } = require('chai');
const {
  constants,    // Common constants, like the zero address and largest integers
  expectEvent,  // Assertions for emitted events
  expectRevert, // Assertions for transactions that should fail
} = require('@openzeppelin/test-helpers');
const { web3 } = require('@openzeppelin/test-helpers/src/setup');

const { ZERO_ADDRESS } = constants;

const NFT = artifacts.require('NFT');
const Marketplace = artifacts.require('Marketplace');
const ERC20 = artifacts.require("MockERC20");


contract('Marketplace', (accounts) => {
    const [owner, recipient, newNftContract, newFeeDestination, newApprovedToken] = accounts;

    let nft = null;
    let marketplace = null;
    let erc20 = null;

    before(async () => {
        nft = await NFT.deployed();
        marketplace = await Marketplace.deployed();
        erc20 = await ERC20.new();
    });

    it('reverts when not owner try to update asset address, fee, fee destination', async function () {
        await expectRevert(
            marketplace.updateAssetAddress(newNftContract, { from: recipient }),
            'caller is not the owner',
        );
        await expectRevert(
            marketplace.updateFee(400, 600, { from: recipient }),
            'caller is not the owner',
        );
        await expectRevert(
            marketplace.updateFeeDestination(newFeeDestination, {from: recipient}),
            'caller is not the owner',
        );
    });
    
    it('should emit event TokenFeeChanged and CoinFeeChanged when update fee', async function () {
        const updateFee = await marketplace.updateFee(0, 600);

        expect(await marketplace.platformFeeInToken()).to.be.bignumber.equal('0');
        expect(await marketplace.platformFeeInCoin()).to.be.bignumber.equal('600');
        expectEvent(updateFee, 'CoinFeeChanged', {
            account: owner,
            newFee: ('600'),
            oldFee: ('500')
        });
    });

    it('should change Fee Destination', async function () {
        await marketplace.updateFeeDestination(newFeeDestination, { from: owner });
        const feeDestination = await marketplace.feeDestination();
        expect(await feeDestination).to.be.equal(newFeeDestination);
    });

    it('should add approved currency for buy', async function () {
        await marketplace.addApprovedToken(newApprovedToken);
        const approvedTokens = await marketplace.approvedTokens(newApprovedToken);

        expect(await approvedTokens).to.be.equal(true);
    })

    it('should delete approved currency for buy', async function () {
        await marketplace.deleteApprovedToken(newApprovedToken)
        const approvedTokens = await marketplace.approvedTokens(newApprovedToken);

        expect(await approvedTokens).to.be.equal(false);
    })

    it('should put token on sale', async function () {
        await nft.mint('metadata', '300');
        
        await expectRevert(
            marketplace.putTokenForSale(1, 0, ZERO_ADDRESS, { from: owner}),
            'Price must be at least 1 wei',
        );

        await expectRevert(
            marketplace.putTokenForSale(1, web3.utils.toWei('1','ether'), newApprovedToken, { from: owner}),
            'Currency must be approved',
        );

        await expectRevert(
            marketplace.putTokenForSale(1, web3.utils.toWei('1','ether'), ZERO_ADDRESS, { from: owner}),
            'ERC721: caller is not owner nor approved.'
        );
        
        await nft.setApprovalForAll(marketplace.address, true, { from: owner});

        const putTokenForSale = await marketplace.putTokenForSale(1, web3.utils.toWei('1','ether'), ZERO_ADDRESS, { from: owner})
        const idToMarketItem = await marketplace.idToMarketItem(1);
        const tokenOwner = await marketplace.tokenOwner(1);
        
        expect(await idToMarketItem.price.toString()).to.be.equal(web3.utils.toWei('1', 'ether'));
        expect(await idToMarketItem.currency).to.be.equal(ZERO_ADDRESS);
        expect(await idToMarketItem.forSale).to.be.true;
        expect(await tokenOwner).to.be.equal(owner);
        expectEvent(putTokenForSale, 'TokenOnSale', {
            owner: owner,
            tokenId: '1',
            price: web3.utils.toWei('1', 'ether'),
            currency: ZERO_ADDRESS
        });
    });

    it('should update token price', async function () {
        await expectRevert(
            marketplace.updateTokenPrice(1, web3.utils.toWei('2', 'ether'), { from: recipient }),
            'Only token owner can do this.',
        );

        const updateTokenPrice = await marketplace.updateTokenPrice(1, web3.utils.toWei('2', 'ether'), { from: owner });
        const idToMarketItem = await marketplace.idToMarketItem(1);

        expect(await idToMarketItem.price.toString()).to.be.equal(web3.utils.toWei('2', 'ether'));
        expectEvent(updateTokenPrice, 'SalePriceChanged', {
            tokenId: '1',
            price: web3.utils.toWei('2', 'ether')
        })
    })

    it('should mark token as not for sale', async function () {
        await expectRevert(
            marketplace.removeTokenFromSale(1, { from: recipient }),
            'Only token owner can do this.',
        );

        const removeTokenFromSale = await marketplace.removeTokenFromSale(1, { from: owner });
        const idToMarketItem = await marketplace.idToMarketItem(1);

        expect(await idToMarketItem.forSale).to.be.false;
        expectEvent(removeTokenFromSale, 'TokenNotOnSale', {
            tokenId: '1',
        });
    });

    it('should bought token for native currency', async function () {
        await expectRevert(
            marketplace.buyToken(1),
            'Token must be on Sale'
        );

        await marketplace.putTokenForSale(1, web3.utils.toWei('1', 'ether'), ZERO_ADDRESS, { from: owner });
        
        await expectRevert(
            marketplace.buyToken(1, { from: recipient, value: web3.utils.toWei('0.1', 'ether') }),
            'Submit the asking price'
        );

        const buyToken = await marketplace.buyToken(1, { from: recipient, value: web3.utils.toWei('1', 'ether') });

        expect(await nft.ownerOf(1)).to.be.equal(recipient);
        expectEvent(buyToken, 'TokenBought', {
            tokenId: '1',
            buyer: recipient,
            currency: ZERO_ADDRESS,
            price: web3.utils.toWei('1', 'ether'),
            fee: web3.utils.toWei('0.06', 'ether'),
            royalty: web3.utils.toWei('0', 'ether')
        })
    });

    it('should bought token for ERC20 currency', async function () {
        await expectRevert(
            marketplace.buyToken(1),
            'Token must be on Sale'
        );

        await expectRevert(
            marketplace.putTokenForSale(1, web3.utils.toWei('1','ether'), erc20.address, { from: recipient}),
            'Currency must be approved',
        );

        await marketplace.addApprovedToken(erc20.address, { from: owner });

        await expectRevert(
            marketplace.putTokenForSale(1, web3.utils.toWei('1','ether'), erc20.address, { from: recipient}),
            'ERC721: caller is not owner nor approved.'
        );

        await nft.setApprovalForAll(marketplace.address, true, { from: recipient});

        await marketplace.putTokenForSale(1, web3.utils.toWei('1', 'ether'), erc20.address, { from: recipient });
        
        await expectRevert(
            marketplace.buyToken(1, { from: owner}),
            'ERC20: transfer amount exceeds allowance.'
        );
        
        await erc20.approve(marketplace.address, web3.utils.toWei('1', 'ether'), { from: owner });

        const buyToken = await marketplace.buyToken(1, { from: owner });

        expect(await nft.ownerOf(1)).to.be.equal(owner);
        expectEvent(buyToken, 'TokenBought', {
            tokenId: '1',
            buyer: owner,
            currency: erc20.address,
            price: web3.utils.toWei('1', 'ether'),
            fee: web3.utils.toWei('0', 'ether'),
            royalty: web3.utils.toWei('0.03', 'ether')
        })
    });

    it('should update token address, if need to change ERC-721 address', async function () {
        await marketplace.updateAssetAddress(newNftContract);
        expect(await marketplace.nftContract()).to.be.equal(newNftContract)
    })
})