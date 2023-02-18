const { expect } = require('chai');
const { expectRevert } = require('@openzeppelin/test-helpers');

const NFT = artifacts.require('NFT');


contract('NFT', (accounts) => {
  const [owner, recipient, operator] = accounts;
  
  let nft = null;

  before(async () => {
    nft = await NFT.deployed();
  });

  it('correctly checks all the supported interfaces', async function() {
    expect(await nft.supportsInterface('0x80ac58cd')).to.equal(true);
    expect(await nft.supportsInterface('0x5b5e139f')).to.equal(true);
    expect(await nft.supportsInterface('0x780e9d63')).to.equal(true);
  });

  it('returns the correct contract name', async function() {
    expect(await nft.name()).to.equal('DemianO Marketplace');
  });

  it('returns the correct contract symbol', async function() {
    expect(await nft.symbol()).to.equal('DEMO');
  });

  it('reverts when queried for non existent token id', async function () {
    await expectRevert(
      nft.tokenURI('123', { from: owner }),
        'URI query for nonexistent token'
    );
  });

  it('should mint NFT, set uri and royalty', async function () {
    let totalSupply = await nft.totalSupply();
    await nft.mint('metadata', '300');
    totalSupply = await nft.totalSupply();
    const balanceOf = await nft.balanceOf(owner);
    const ownerOf = await nft.ownerOf(1);
    const royaltyInfo = await nft.royaltyInfo(1, 100);
    const tokenURI = await nft.tokenURI(1);
    const creator = await nft.creators(1);
    expect(await totalSupply.toString()).to.be.equal('1');
    expect(await balanceOf.toString()).to.be.equal('1');
    expect(await ownerOf).to.be.equal(owner);
    expect(await royaltyInfo.receiver).to.be.equal(creator);
    expect(await +royaltyInfo.royaltyAmount).to.be.equal(3);
    expect(await tokenURI).to.be.equal('metadata');
  });

  it('should transfer NFT from owner to recipient', async function () {
    await nft.safeTransferFrom(owner, recipient, 1, { from: owner });
    const ownerOf = await nft.ownerOf(1);
    expect(await ownerOf).to.be.equal(recipient);
  });

  it('should transfer NFT if caller is approved', async function () {
    await nft.approve(owner, 1, { from: recipient });
    const getApproved = await nft.getApproved(1);
    await nft.safeTransferFrom(recipient, owner, 1, {from: owner});
    const ownerOf = await nft.ownerOf(1);
    expect(await getApproved).to.be.equal(owner);
    expect(await ownerOf).to.be.equal(owner);
  });

  it('should not transfer NFT if caller is not owner or approved', async function () {
    await expectRevert(
      nft.safeTransferFrom(owner, recipient, 1, { from: recipient }),
        'ERC721: transfer caller is not owner nor approved.'
    );
  });

  it('Should allow operator to transfer tokens', async function () {
    await nft.mint('metadata1', '500');
    await nft.mint('metadata2', '400');

    await nft.setApprovalForAll(operator, true, { from: owner });
    const isApprovedForAll = await nft.isApprovedForAll(owner, operator)
    
    await nft.safeTransferFrom(owner, operator, 2, { from: operator });
    await nft.safeTransferFrom(owner, operator, 3, { from: operator });
    
    const tokensOfOwner = await nft.tokensOfOwner(owner);
    const tokensOfOperator = await nft.tokensOfOwner(operator);
    
    expect(await isApprovedForAll).to.be.equal(true);
    expect(await tokensOfOwner.join(',')).to.be.equal('1');
    expect(await tokensOfOperator.join(',')).to.be.equal('2,3');
  });

  it('revert when not owner try to set base extencion, base URI, contract URI', async function () {
    await expectRevert(
        nft.setBaseExtension('.js', { from: recipient }),
        'caller is not the owner',
    );
    await expectRevert(
        nft.setBaseURI('meta', { from: recipient }),
        'caller is not the owner',
    );
    await expectRevert(
        nft.setContractURI('ipfs', {from: recipient}),
        'caller is not the owner',
    );
  });

  it('return correctly concatenated tokenURI', async function () {
    await nft.setBaseURI('meta/', { from: owner });
    await nft.setBaseExtension('.json', { from: owner });
    const tokenURI = await nft.tokenURI(1);
    
    expect(await tokenURI).to.be.equal('meta/1.json');
  });
});
