const { ethers } = require("ethers");

require("dotenv").config();
require("@nomiclabs/hardhat-ethers");
require("@nomiclabs/hardhat-etherscan");
require("@openzeppelin/hardhat-upgrades");

module.exports = {
    networks: {
        mainnet: {
            accounts: [process.env.PRIVATE_KEY],
            chainId: 1,
            url: "https://rpc.ankr.com/eth/29b769e84f175da6e6245e6cdefb0fbfd91cca5f8bbf614f860e260e1d070f27",
        },
        bsc: {
            accounts: [process.env.PRIVATE_KEY],
            chainId: 56,
            url: "https://bsc-dataseed.binance.org/",
        },
        matic: {
            accounts: [process.env.PRIVATE_KEY],
            chainId: 137,
            url: "https://rpc.ankr.com/polygon/29b769e84f175da6e6245e6cdefb0fbfd91cca5f8bbf614f860e260e1d070f27",
            gasPrice: ethers.utils.parseUnits("100", "gwei").toNumber(),
        },
        bscTestnet: {
            accounts: [process.env.PRIVATE_KEY],
            chainId: 97,
            url: "https://data-seed-prebsc-1-s1.binance.org:8545/",
        },
    },
    solidity: {
        compilers: [
            {
                version: "0.5.16",
            },
            {
                version: "0.8.10",
                settings: {
                    optimizer: {
                        enabled: true,
                        runs: 100,
                    },
                },
            },
        ],
    },
    etherscan: {
        apiKey: {
            mainnet: process.env.ETHERSCAN_API_KEY || "",
            bsc: process.env.BSCSCAN_API_KEY || "",
            polygon: process.env.POLYGONSCAN_API_KEY || "",
            bscTestnet: process.env.TESTBSCSCAN_API_KEY || "",
        },
    },
};
