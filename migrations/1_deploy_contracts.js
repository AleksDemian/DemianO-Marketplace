const { deployProxy } = require("@openzeppelin/truffle-upgrades");

const NFT = artifacts.require("NFT");

const Marketplace = artifacts.require("Marketplace");

const AuctionEngine = artifacts.require("AuctionEngine");

const DemianO = artifacts.require("DemianO");

const { 
  name, 
  symbol, 
  contractURI, 
  approvedToken, 
  feeDestination, 
  platformFeeInCoin, 
  platformFeeInToken, 
  token 
} = require('../secrets.json');

module.exports = async function(deployer) {
  await deployProxy(NFT, [name, symbol, contractURI], { deployer, kind: 'uups' });
  const ERC721 = await NFT.deployed();
  await deployProxy(Marketplace, [ERC721.address, approvedToken, feeDestination, platformFeeInCoin, platformFeeInToken], { deployer, kind: 'uups' });
  const marketplace = await Marketplace.deployed();
  await deployProxy(AuctionEngine, [token, marketplace.address, feeDestination], { deployer, kind: 'uups' });
  await deployProxy(DemianO, { deployer, kind: 'uups' });
};




