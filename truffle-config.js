const HDWalletProvider = require('@truffle/hdwallet-provider');
const { privateKeys, BSCSCANAPIKEY} = require('./secrets.json');


module.exports = {
  plugins: [
    'truffle-plugin-verify'
  ],
  api_keys: {
    bscscan: BSCSCANAPIKEY
  },
  networks: {
   development: {
     host: "127.0.0.1",
     port: 7545,
     network_id: "*"
   },
   test: {
     host: "127.0.0.1",
     port: 8545,
     network_id: "*"
    },
   testnet: {
      provider: () => {
        return new HDWalletProvider({
          privateKeys: privateKeys,
          providerOrUrl: `https://data-seed-prebsc-1-s1.binance.org:8545/`,
        });
      },
      network_id: 97,
      confirmations: 2,
      timeoutBlocks: 200,
      skipDryRun: true
    },
    bsc: {
      provider: () => {
        return new HDWalletProvider({
          privateKeys: privateKeys,
          providerOrUrl: `wss://bsc-mainnet.nodereal.io/ws/v1/64a9df0874fb4a93b9d0a3849de012d3`,
        });
      },
      network_id: 56,
      confirmations: 2,
      timeoutBlocks: 200,
      skipDryRun: true
    },
  },
   compilers: {
    solc: {
      version: "0.8.7",
      settings: {          
       optimizer: {
         enabled: false,
         runs: 200
        },
      }
    }
   },
};
