const { expect } = require('chai');
const {
  constants,    // Common constants, like the zero address and largest integers
  expectEvent,  // Assertions for emitted events
  expectRevert, // Assertions for transactions that should fail
  time,
} = require('@openzeppelin/test-helpers');
const { web3 } = require('@openzeppelin/test-helpers/src/setup');
var chai = require('chai');
var BN = require('bn.js');
var bnChai = require('bn-chai');
chai.use(bnChai(BN));

const { ZERO_ADDRESS } = constants;

const NFT = artifacts.require('NFT');
const ERC20 = artifacts.require("MockERC20");
const AuctionEngineV4 = artifacts.require("AuctionEngineV4");


contract('AuctionEngine', (accounts) => {
    const [owner, bidder, newNftContract, newFeeDestination, newApprovedToken] = accounts;

    let nft = null;
    let auction = null;
    let erc20 = null;
    
    before(async () => {
        nft = await NFT.deployed();
        auction = await AuctionEngineV4.deployed();
        erc20 = await ERC20.new();
    });

    
    it("Should create an auction", async function() {
        await nft.mint('metadata', '500', {from: owner});
        await nft.setApprovalForAll(auction.address, true, { from: owner });
        await auction.createAuction(nft.address, 1, web3.utils.toWei('0.1', 'ether'), 0, 30, ZERO_ADDRESS, { from:owner });
        expect(await auction.getTotalAuctions()).to.be.eq.BN(1);
        expect(await nft.ownerOf(1)).to.be.equal(auction.address);
    });

    it('Should cancel auction if have no bid', async function () {
        await auction.cancelAuction(0,{from:owner});
        expect(await nft.ownerOf(1)).to.be.equal(owner);
    });

    it('Should bid for coin currency', async function () {
        await auction.createAuction(nft.address, 1, web3.utils.toWei('0.1', 'ether'), 0, 30, ZERO_ADDRESS, { from:owner });
        await auction.bid(1, web3.utils.toWei('0.2', 'ether'), {from:bidder, value: web3.utils.toWei('0.2', 'ether')});
        expect(await auction.getCurrentBidAmount(1)).to.be.eq.BN(web3.utils.toWei('0.2', 'ether'));
        expect(await auction.getCurrentBidOwner(1)).to.be.equal(bidder); 
    });

    it('Should transfer the asset to the winner when auction is finalize', async function () {
        await time.increase(30)
        const isFinished = await auction.isFinished(1);
        const getWinner = await auction.getWinner(1);
        expect(isFinished).to.be.equal(true);
        expect(getWinner).to.be.equal(bidder);
        const finalize = await auction.finalize(1, {from:bidder});
        expect(await nft.ownerOf(1)).to.be.equal(bidder);
        expectEvent(finalize, 'AuctionFinalized', {
            asset: nft.address,
            tokenId: '1',
            buyer: bidder,
            auctionIndex: '1',
            currency: ZERO_ADDRESS, 
            price: web3.utils.toWei('0.2', 'ether'),
            fee: web3.utils.toWei('0.01', 'ether'),
            royalty:'0'
        })
    });

    it('Should bid and finalize for ERC20 currency', async function () {
        await nft.setApprovalForAll(auction.address, true, { from: bidder });
        await auction.createAuction(nft.address, 1, web3.utils.toWei('1', 'ether'), 0, 30, erc20.address, { from:bidder });
        await erc20.approve(auction.address, web3.utils.toWei('2', 'ether'), {from:owner});
        await auction.bid(2, web3.utils.toWei('2', 'ether'), {from:owner});
        expect(await auction.getCurrentBidAmount(2)).to.be.eq.BN(web3.utils.toWei('2', 'ether'));
        expect(await auction.getCurrentBidOwner(2)).to.be.equal(owner); 
        await time.increase(30)
        const finalize = await auction.finalize(2, {from:owner});
        expect(await nft.ownerOf(1)).to.be.equal(owner);
        expectEvent(finalize, 'AuctionFinalized', {
            asset: nft.address,
            tokenId: '1',
            buyer: owner,
            auctionIndex: '2',
            currency: erc20.address, 
            price: web3.utils.toWei('2', 'ether'),
            fee: web3.utils.toWei('0.1', 'ether'),
            royalty: web3.utils.toWei('0.1', 'ether')
        })   
    });

    it('Only owner of asset can create auction', async function () {
        await expectRevert(
            auction.createAuction(nft.address, 1, web3.utils.toWei('1', 'ether'), 0, 30, erc20.address, { from:bidder }),
            'Only token owner can do this',
        );

        await auction.createAuction(nft.address, 1, web3.utils.toWei('1', 'ether'), 0, 30, erc20.address, { from:owner });
        expect(await auction.getTotalAuctions()).to.be.eq.BN(4);
        expect(await nft.ownerOf(1)).to.be.equal(auction.address);
    });

    it('Only auction owner can cancel auction', async function () {
        await expectRevert(
            auction.cancelAuction(3, {from:bidder}),
            'Only auction owner'
        )
    });

    it('Can not cancel auction if has a bid', async function () {
        await erc20.transfer(bidder, web3.utils.toWei('20', 'ether'), {from:owner});
        await erc20.approve(auction.address, web3.utils.toWei('2', 'ether'), {from:bidder});
        await auction.bid(3, web3.utils.toWei('2', 'ether'), {from:bidder});

        await expectRevert(
            auction.cancelAuction(3, {from:owner}),
            'Auction has a bid'
        )
    });

    it('Can make a bid only on active auction', async function () {
        await expectRevert(
            auction.bid(2, web3.utils.toWei('2', 'ether'), {from:bidder}),
            'Auction must be active'
        )
    });

    it('Did not beat the previous bid', async function () {
        await expectRevert(
            auction.bid(3, web3.utils.toWei('1', 'ether'), {from:owner}),
            "You don't outbid"
        )
    });

    it('To get winner auction must be finished', async function () {
        await expectRevert(
            auction.getWinner(3),
            'Auction must be finished'
        )
        await time.increase(30)
        expect(await auction.getWinner(3)).to.be.equal(bidder)
    });

    it('Auction can be finalized only once', async function () {
        await expectRevert(
            auction.finalize(2, {from:owner}),
            'Auction can be finalized only once'
        )
        const finalize = await auction.finalize(3, {from:bidder});
        expect(await nft.ownerOf(1)).to.be.equal(bidder);
        expectEvent(finalize, 'AuctionFinalized', {
            asset: nft.address,
            tokenId: '1',
            buyer: bidder,
            auctionIndex: '3',
            currency: erc20.address, 
            price: web3.utils.toWei('2', 'ether'),
            fee: web3.utils.toWei('0.1', 'ether'),
            royalty: '0'
        })  
    });
})