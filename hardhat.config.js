require("@nomiclabs/hardhat-ethers");
require("@nomiclabs/hardhat-etherscan");
require("@nomiclabs/hardhat-waffle");
require("@nomiclabs/hardhat-web3");
require("hardhat-gas-reporter");
require("solidity-coverage");

const credentials = require("./.env.js");
const INFURA_PROJECT_ID = credentials.Infura;
const METAMASK_PRIVATE_KEY = credentials.privateKey;
const ETHERSCAN_KEY = credentials.etherscan;
const COINMARKETCAP_KEY = credentials.coinmarketcap;

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  solidity: {
    version: "0.8.10",
    //		version: "0.8.9",

    /*		compilers: [
		  {
			version: "0.7.6"
		  },
		  {
			version: "0.8.9"
		  }
		],
*/ settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
    /*		overrides: {
      "contracts/CivPositionMgr.sol": {
        version: "0.7.6",
        settings: {optimizer: {enabled: true, runs: 200} }
      },
      "contracts/CivKeeper.sol": {
        version: "0.7.6",
        settings: {optimizer: {enabled: true, runs: 200} }
      },
      "contracts/CivTradeHelperFunctions.sol": {
        version: "0.7.6",
        settings: {optimizer: {enabled: true, runs: 200} }
      },
      "contracts/MinimalForwarder.sol": {
        version: "0.8.9",
        settings: {optimizer: {enabled: true, runs: 200} }
      },
    },
*/
  },

  abiExporter: {
    path: "./abi",
    runOnCompile: true,
    clear: true,
    flat: true,
    only: [],
    spacing: 0,
    pretty: false,
  },

  etherscan: {
    apiKey: `${ETHERSCAN_KEY}`,
  },

  //   defender: {
  //     apiKey: `${DEFENDER_API}`,
  //     apiSecret: `${DEFENDER_SECRET}`,
  //   },

  gasReporter: {
    currency: "USD",
    coinmarketcap: `${COINMARKETCAP_KEY}`,
    gasPrice: 100,
    token: "ETH",
    noColors: true,
    onlyCalledMethods: true,
    showTimeSpent: true,
  },

  docgen: {
    path: "./docs",
    clear: true,
    runOnCompile: false,
  },

  contractSizer: {
    alphaSort: false,
    disambiguatePaths: true,
    runOnCompile: false,
    strict: false,
  },

  defaultNetwork: "hardhat",

  networks: {
    hardhat: {
      forking: {
        url: "https://eth-mainnet.alchemyapi.io/v2/xKgevWjCDGsK7HkJ7Votw83FLLQRsgfB",
      },
    },
    mainnet: {
      chainId: 1,
      url: `https://mainnet.infura.io/v3/${INFURA_PROJECT_ID}`,
      //			url: `https://eth-mainnet.alchemyapi.io/v2/${ALCHEMY_API}`,
      accounts: [`0x${METAMASK_PRIVATE_KEY}`],
      //		gas: 7000000,
      skipDryRun: true,
    },
    ropsten: {
      chainId: 3,
      url: `https://ropsten.infura.io/v3/${INFURA_PROJECT_ID}`,
      accounts: [`0x${METAMASK_PRIVATE_KEY}`],
      //		gas: 7000000,
      skipDryRun: true,
    },
    rinkeby: {
      chainId: 4,
      url: `https://rinkeby.infura.io/v3/${INFURA_PROJECT_ID}`,
      //			url: `https://eth-rinkeby.alchemyapi.io/v2/${ALCHEMYRINKEBY_API}`,
      accounts: [`0x${METAMASK_PRIVATE_KEY}`],
      //		gasPrice: 25000000000,
      gas: 7000000,
      skipDryRun: true,
    },
    optimism: {
      chainId: 10,
      url: `https://optimism-mainnet.infura.io/v3/${INFURA_PROJECT_ID}`,
      accounts: [`0x${METAMASK_PRIVATE_KEY}`],
      //		gasPrice: 25000000000,
      //		gas: 7000000,
      skipDryRun: true,
    },
    kovan: {
      chainId: 42,
      url: `https://kovan.infura.io/v3/${INFURA_PROJECT_ID}`,
      //			url: `https://eth-kovan.alchemyapi.io/v2/${ALCHEMYKOVAN_API}`,
      accounts: [`0x${METAMASK_PRIVATE_KEY}`],
      //		gasPrice: 25000000000,
      gas: 7000000,
      skipDryRun: true,
    },
    polygonmainnet: {
      chainId: 137,
      //  url: `https://rpc-mainnet.maticvigil.com/v1/${POLYGON_PROJECT_ID}`,
      //  url: `https://polygon-rpc.com/`,
      //			url: `https://polygon-mainnet.g.alchemy.com/v2/${ALCHEMYPOLYGON_API}`,
      url: `https://polygon-mainnet.infura.io/v3/${INFURA_PROJECT_ID}`,
      accounts: [`0x${METAMASK_PRIVATE_KEY}`],
      gas: 7000000,
      gasPrice: 550000000000, //  750000000000 is 750 gwei... still won't work
      skipDryRun: true,
    },
    arbitrum: {
      chainId: 42161,
      url: `https://arbitrum-mainnet.infura.io/v3/${INFURA_PROJECT_ID}`,
      accounts: [`0x${METAMASK_PRIVATE_KEY}`],
      //		gas: 7000000,
      //		gasPrice: 35000000000,
      skipDryRun: true,
    },
    polygonmumbai: {
      chainId: 80001,
      //		url: `https://rpc-mumbai.maticvigil.com/v1/${POLYGON_PROJECT_ID}`,
      url: `https://polygon-mumbai.infura.io/v3/${INFURA_PROJECT_ID}`,
      accounts: [`0x${METAMASK_PRIVATE_KEY}`],
      gas: 7000000,
      gasPrice: 35000000000,
      skipDryRun: true,
    },
  },

  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts",
  },

  mocha: {
    timeout: 20000,
  },
};
