const { utils, constants } = require("ethers");
const hre = require("hardhat");

const sleep = (delay) => new Promise((resolve) => setTimeout(resolve, delay * 1000));

async function main() {
    const ethers = hre.ethers;
    const upgrades = hre.upgrades;

    console.log("network:", await ethers.provider.getNetwork());

    const signer = (await ethers.getSigners())[0];
    const signerAddr = await signer.getAddress();
    console.log("signer:", signerAddr);

    let nftTokenAddress = "0x7051A68dA79da816D4cb99f97BBe36632Ce44d8a";
    let plutusSwapAddress = "0x84dc840240d204CC36ed5be2411BB155BBBaAadC";
    let plutusLootboxFactory = "";

    let deployFlag = {
        deployAluturaNFT: false,
        deployAlturaSwap: false,
        upgradeAlturaSwap: false,
        deployAlturaLootbox: true,
        deployAlturaLootboxFactory: false,
        upgradeAlturaLootboxFactory: false,
    };

    /**
     *  Deploy Altura NFT Token
     */
    if (deployFlag.deployAluturaNFT) {
        const AlturaNFTV2 = await ethers.getContractFactory("AlturaNFTV2", {
            signer: signer,
        });

        const nftContract = await AlturaNFTV2.deploy();
        await nftContract.deployed();

        nftContract.attach(nftContract.address).initialize("AlturaNFTV2", "", signerAddr, true);

        console.log("Altura NFT V2 token deployed to:", nftContract.address);
        nftTokenAddress = nftContract.address;

        await sleep(60);
        await hre.run("verify:verify", {
            address: nftContract.address,
            contract: "contracts/V2/AlturaNFTV2.sol:AlturaNFTV2",
            constructorArguments: [],
        });

        console.log("Altura NFT contract verified");
    }

    /**
     *  Deploy AlturaNFT Swap
     */
    if (deployFlag.deployAlturaSwap) {
        const PlutusSwap = await ethers.getContractFactory("AlturaNFTFactoryV2", {
            signer: (await ethers.getSigners())[0],
        });

        const swapContract = await upgrades.deployProxy(PlutusSwap, ["0xAeAF8FcC925d254fC62051a12fF13da1aFfa5Ed4"], {
            initializer: "initialize",
            kind: "uups",
        });
        await swapContract.deployed();

        console.log("Altura NFT Swap deployed to:", swapContract.address);
        plutusSwapAddress = swapContract.address;
    }

    /**
     *  Upgrade AlturaNFT Swap
     */
    if (deployFlag.upgradeAlturaSwap) {
        const PlutusSwapV2 = await ethers.getContractFactory("AlturaNFTFactoryV2", {
            signer: (await ethers.getSigners())[0],
        });

        await upgrades.upgradeProxy(plutusSwapAddress, PlutusSwapV2);

        console.log("Altura NFT Swap V2 upgraded");
    }

    /**
     *  Deploy Altura Lootbox
     */
    if (deployFlag.deployAlturaLootbox) {
        const AlturaLootboxV2 = await ethers.getContractFactory("AlturaLootboxV2", {
            signer: signer,
        });

        const lootboxContract = await AlturaLootboxV2.deploy();
        await lootboxContract.deployed();

        lootboxContract
            .attach(lootboxContract.address)
            .initialize("Altura Lootbox V2", "", constants.AddressZero, constants.AddressZero, 0, 0, signerAddr);

        console.log("Altura Lootbox V2 token deployed to:", lootboxContract.address);
        const address = lootboxContract.address;

        await sleep(60);
        await hre.run("verify:verify", {
            address: address,
            contract: "contracts/V2/AlturaLootboxV2.sol:AlturaLootboxV2",
            constructorArguments: [],
        });

        console.log("Altura Lootbox contract verified");
    }

    /**
     *  Deploy AlturaLootbox Factory
     */
    if (deployFlag.deployAlturaLootboxFactory) {
        const PlutusLootbox = await ethers.getContractFactory("AlturaLootboxFactoryV2", {
            signer: (await ethers.getSigners())[0],
        });

        const factoryContract = await upgrades.deployProxy(
            PlutusLootbox,
            ["0x94ec0Ba4c17C0a658B51ce375F73b1B18d2650cD"],
            {
                initializer: "initialize",
                kind: "uups",
            },
        );
        await factoryContract.deployed();

        console.log("Altura Lootbox factory deployed to:", factoryContract.address);
    }

    /**
     *  Upgrade Altura Lootbox factory
     */
    if (deployFlag.upgradeAlturaLootboxFactory) {
        const PlutusLootboxV2 = await ethers.getContractFactory("AlturaLootboxFactoryV2", {
            signer: (await ethers.getSigners())[0],
        });

        await upgrades.upgradeProxy(plutusLootboxFactory, PlutusLootboxV2);

        console.log("Altura Lootbox Factory V2 upgraded");
    }
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
