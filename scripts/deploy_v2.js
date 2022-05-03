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

    let deployFlag = {
        deployAluturaNFT: false,
        deployAlturaSwap: false,
        upgradeAlturaSwap: true,
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
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
