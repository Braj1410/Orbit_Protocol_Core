import "@nomicfoundation/hardhat-toolbox";
import "@openzeppelin/hardhat-upgrades";
import "hardhat-tracer";

import { HardhatUserConfig } from "hardhat/types";

const config: HardhatUserConfig = {
  solidity: {
    compilers: [
      {
        version: "0.8.28",
        settings: {
          optimizer: {
            enabled: true,
            runs: 10000,
          },
          viaIR: true,
        },
      },
    ],
  },
  networks: {
    hardhat: {
      forking: {
        url: "https://rpc.vvs.finance",
        enabled: false,
      },
      loggingEnabled: true,
      throwOnCallFailures: true,
      throwOnTransactionFailures: true,
      hardfork: "merge",
    },
    fg: {
      url: "HTTP://127.0.0.1:8545",
      gasPrice: "auto",
      gas: "auto",
    },
  },
};

export default config;
