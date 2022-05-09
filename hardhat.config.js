const { ethers } = require("ethers");

require("dotenv").config();
require("@nomiclabs/hardhat-ethers");
require("@nomiclabs/hardhat-etherscan");
require("@openzeppelin/hardhat-upgrades");

module.exports = {
    networks: {
        testnet: {
            url: process.env.NODE_URL,
            accounts: [process.env.PRIVATE_KEY],
        },
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
    },
    solidity: {
        compilers: [
            {
                version: "0.5.16",
            },
            {
                version: "0.8.4",
                settings: {
                    optimizer: {
                        enabled: true,
                        runs: 100,
                    },
                },
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
        apiKey: "Y5HQ4K5GQ7Y4UPVJW4ZGWEZ59BIV4XWTFU",
    },
};
