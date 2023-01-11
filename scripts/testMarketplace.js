const hre = require("hardhat");
const {
    time,
    loadFixture,
} = require("@nomicfoundation/hardhat-network-helpers");
const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");
const { expect } = require("chai");
const { ethers } = require("hardhat");

// Gets Balance of an Address
const getBalance = async (address) => {
    const balanceBigInt = await ethers.provider.getBalance(address);
    return hre.ethers.utils.formatEther(balanceBigInt);
};

// Deploy Contract
const deploy = async (name) => {
    const ContractFactory = await hre.ethers.getContractFactory(name);
    const Contract = await ContractFactory.deploy();
    await Contract.deployed();
    return Contract;
};

const main = async () => {
    let beforeBalance, afterBalance;

    const ADDRESS_ZERO = ethers.constants.AddressZero;
    const ETHER_1 = hre.ethers.utils.parseEther("1");

    // Getting Users
    const [user1, user2, user3, user4, user5] = await hre.ethers.getSigners();

    // Deploying Contracts
    const NFTCollection = await deploy("NFTCollection");
    const NFTMarketplace = await deploy("NFTMarketplace");

    // Minting NFT
    await NFTCollection.connect(user1).mint("Test");
    expect(await NFTCollection.connect(user1).ownerOf(1)).to.equal(
        user1.address
    );

    // Giving approval to Marketplace
    await NFTCollection.connect(user1).approve(NFTMarketplace.address, 1);
    expect(await NFTCollection.connect(user1).getApproved(1)).to.equal(
        NFTMarketplace.address
    );

    // Listing NFT
    let listParams = [
        (_collection = NFTCollection.address),
        (_id = 1),
        (_payment = ADDRESS_ZERO),
        (_listPrice = ETHER_1),
    ];
    await NFTMarketplace.setListing(...listParams);
    expect(await NFTCollection.ownerOf(1)).to.equal(NFTMarketplace.address);

    // Buying NFT
    let buyParams = [(_collection = NFTCollection.address), (_id = 1)];
    await NFTMarketplace.connect(user2).buyListing(...buyParams, {
        value: hre.ethers.utils.parseEther("1"),
    });
    expect(await NFTCollection.ownerOf(1)).to.equal(user2.address);
};

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
