require("@nomicfoundation/hardhat-toolbox");

const configuredNetworks = {};

if (process.env.RPC_URL && process.env.PRIVATE_KEY) {
  configuredNetworks.target = {
    url: process.env.RPC_URL,
    accounts: [process.env.PRIVATE_KEY]
  };
}

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    version: "0.8.24",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      }
    }
  },
  networks: configuredNetworks
};
