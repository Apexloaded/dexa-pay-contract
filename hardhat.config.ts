import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@openzeppelin/hardhat-upgrades";
import "dotenv/config";

const KEY = process.env.PRIVATE_KEY;
const config: HardhatUserConfig = {
  solidity: {
    compilers: [
      {
        version: "0.8.27",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
    ],
  },
  defaultNetwork: "hardhat",
  networks: {
    hardhat: {
      chainId: 3117,
    },
    testnet: {
      url: process.env.BASE_RPC_TESTNET,
      accounts: [KEY ? KEY : ""],
    },
    mainnet: {
      url: process.env.BASE_RPC_MAINNET,
      accounts: [KEY ? KEY : ""],
    },
  },
  etherscan: {
    apiKey: "",
  },
};

export default config;
