require("@nomiclabs/hardhat-truffle5");
require("@nomiclabs/hardhat-etherscan");
require("@nomiclabs/hardhat-ethers");
require("dotenv").config();
require("hardhat-gas-reporter");
require("solidity-coverage");
const {removeConsoleLog} = require("hardhat-preprocessor");

module.exports = {
  defaultNetwork: "hardhat",
  networks: {
    hardhat: {
      chainId: 1,
      forking: {
        url: `https://mainnet.infura.io/v3/${process.env.INFURA_KEY}`,
      },
      allowUnlimitedContractSize: true,
    },
    mainnet: {
      url: `https://mainnet.infura.io/v3/${process.env.INFURA_KEY}`,
      accounts: {
        mnemonic: process.env.MNEMONIC,
      },
      allowUnlimitedContractSize: true,
    },
    ropsten: {
      url: `https://ropsten.infura.io/v3/${process.env.INFURA_KEY}`,
      accounts: {
        mnemonic: process.env.MNEMONIC,
      },
      allowUnlimitedContractSize: true,
    },
    rinkeby: {
      url: `https://rinkeby.infura.io/v3/${process.env.INFURA_KEY}`,
      accounts: {
        mnemonic: process.env.MNEMONIC,
      },
      allowUnlimitedContractSize: true,
    },
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_APIKEY,
  },
  solidity: {
    version: "0.6.12",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  mocha: {
    timeout: 20000000,
  },
  gasReporter: {
    enabled: true,
    coinmarketcap: process.env.COINMARKETCAP,
    currency: "USD",
    gasPrice: 61,
  },
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts",
  },
  preprocess: {
    eachLine: removeConsoleLog((hre) => hre.network.name !== "hardhat" && hre.network.name !== "localhost"),
  },
};
