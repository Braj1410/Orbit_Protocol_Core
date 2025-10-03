const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("TLD Quick Integration Test", function () {
    it("Should deploy and connect all TLD system components", async function () {
        console.log("Deploying TLD system...");
        const [owner] = await ethers.getSigners();
        
        // Deploy minimal required contracts
        const OrbitRegistry = await ethers.getContractFactory("OrbitRegistry");
        const orbit = await OrbitRegistry.deploy();
        console.log("✓ OrbitRegistry deployed");
        
        const OrbitRoot = await ethers.getContractFactory("OrbitRoot");
        const orbitRoot = await OrbitRoot.deploy(orbit.target || orbit.address);
        console.log("✓ OrbitRoot deployed");
        
        const Blocklist = await ethers.getContractFactory("Blocklist");
        const blocklist = await Blocklist.deploy();
        await blocklist.initialize();
        console.log("✓ Blocklist deployed");
        
        const TLDStorage = await ethers.getContractFactory("TLDStorage");
        const storage = await TLDStorage.deploy();
        console.log("✓ TLDStorage deployed");
        
        const TLDAuctionModule = await ethers.getContractFactory("TLDAuctionModule");
        const auction = await TLDAuctionModule.deploy(storage.target || storage.address);
        console.log("✓ TLDAuctionModule deployed");
        
        const TLDRevenueModule = await ethers.getContractFactory("TLDRevenueModule");
        const revenue = await TLDRevenueModule.deploy(
            storage.target || storage.address,
            owner.address
        );
        console.log("✓ TLDRevenueModule deployed");
        
        const TLDRegistrarFactory = await ethers.getContractFactory("TLDRegistrarFactory");
        const registrarFactory = await TLDRegistrarFactory.deploy(
            orbit.target || orbit.address,
            orbitRoot.target || orbitRoot.address
        );
        console.log("✓ TLDRegistrarFactory deployed");
        
        const TLDFactoryMinimalist = await ethers.getContractFactory("TLDFactoryMinimalist");
        const factory = await TLDFactoryMinimalist.deploy(
            storage.target || storage.address
        );
        console.log("✓ TLDFactoryMinimalist deployed");
        
        // Configure
        await storage.authorize(factory.target || factory.address);
        await storage.authorize(auction.target || auction.address);
        await storage.authorize(revenue.target || revenue.address);
        
        // Set modules in factory
        await factory.setModules(
            revenue.target || revenue.address,
            auction.target || auction.address,
            registrarFactory.target || registrarFactory.address
        );
        
        await auction.setFactory(factory.target || factory.address);
        await revenue.setFactory(factory.target || factory.address);
        await registrarFactory.setTLDFactory(factory.target || factory.address);
        await orbitRoot.addController(registrarFactory.target || registrarFactory.address);
        console.log("✓ System configured");
        
        // Test basic TLD creation
        const tx = await factory.createTLD(
            "test",
            ethers.parseEther ? ethers.parseEther("0.01") : ethers.utils.parseEther("0.01"),
            { value: ethers.parseEther ? ethers.parseEther("1000") : ethers.utils.parseEther("1000") }
        );
        await tx.wait();
        console.log("✓ TLD created successfully");
        
        // Verify TLD exists
        const tld = await storage.getTLD(1);
        expect(tld.name).to.equal("test");
        console.log("✓ TLD verified");
        
        console.log("\n✅ All tests passed! TLD system is working correctly.");
    });
});