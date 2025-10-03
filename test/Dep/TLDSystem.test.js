const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("TLD System Integration Test", function () {
    let orbit, orbitRoot, blocklist;
    let storageModule, auctionModule, revenueModule, registrarFactory;
    let tldFactory;
    let owner, user1, user2, treasury;
    
    beforeEach(async function () {
        [owner, user1, user2, treasury] = await ethers.getSigners();
        
        // Deploy core contracts
        const OrbitRegistry = await ethers.getContractFactory("OrbitRegistry");
        orbit = await OrbitRegistry.deploy();
        await orbit.waitForDeployment();
        
        const OrbitRoot = await ethers.getContractFactory("OrbitRoot");
        orbitRoot = await OrbitRoot.deploy(await orbit.getAddress());
        await orbitRoot.waitForDeployment();
        
        const Blocklist = await ethers.getContractFactory("Blocklist");
        blocklist = await Blocklist.deploy();
        await blocklist.waitForDeployment();
        await blocklist.initialize();
        
        // Deploy modules
        const TLDStorage = await ethers.getContractFactory("TLDStorage");
        storageModule = await TLDStorage.deploy();
        await storageModule.waitForDeployment();
        
        const TLDAuctionModule = await ethers.getContractFactory("TLDAuctionModule");
        auctionModule = await TLDAuctionModule.deploy(await storageModule.getAddress());
        await auctionModule.waitForDeployment();
        
        const TLDRevenueModule = await ethers.getContractFactory("TLDRevenueModule");
        revenueModule = await TLDRevenueModule.deploy(
            await storageModule.getAddress(),
            treasury.address
        );
        await revenueModule.waitForDeployment();
        
        const TLDRegistrarFactory = await ethers.getContractFactory("TLDRegistrarFactory");
        registrarFactory = await TLDRegistrarFactory.deploy(
            await orbit.getAddress(),
            await orbitRoot.getAddress()
        );
        await registrarFactory.waitForDeployment();
        
        // Deploy main factory
        const TLDFactoryFull = await ethers.getContractFactory("TLDFactoryFull");
        tldFactory = await TLDFactoryFull.deploy(
            await storageModule.getAddress(),
            await auctionModule.getAddress(),
            await revenueModule.getAddress(),
            await registrarFactory.getAddress(),
            await blocklist.getAddress()
        );
        await tldFactory.waitForDeployment();
        
        // Configure access control
        await storageModule.authorize(await tldFactory.getAddress());
        await storageModule.authorize(await auctionModule.getAddress());
        await storageModule.authorize(await revenueModule.getAddress());
        
        await auctionModule.setFactory(await tldFactory.getAddress());
        await revenueModule.setFactory(await tldFactory.getAddress());
        await registrarFactory.setTLDFactory(await tldFactory.getAddress());
        await orbitRoot.addController(await registrarFactory.getAddress());
    });
    
    describe("TLD Creation", function () {
        it("Should create a new TLD", async function () {
            const tldName = "eth";
            const registrationFee = ethers.utils.parseEther("0.01");
            const duration = 365 * 24 * 60 * 60; // 1 year
            const tldFee = ethers.utils.parseEther("1000");
            
            await expect(
                tldFactory.connect(user1).createTLD(
                    tldName,
                    registrationFee,
                    duration,
                    { value: tldFee }
                )
            ).to.emit(tldFactory, "TLDCreated");
            
            // Verify TLD was created
            const tld = await tldFactory.getTLDFull(1);
            expect(tld.name).to.equal(tldName);
            expect(tld.owner).to.equal(user1.address);
            expect(tld.registrationFee).to.equal(registrationFee);
            expect(tld.isActive).to.be.true;
            
            // Verify NFT was minted
            expect(await tldFactory.ownerOf(1)).to.equal(user1.address);
            
            // Verify registrar was deployed
            const registrarAddress = await registrarFactory.getRegistrar(1);
            expect(registrarAddress).to.not.equal(ethers.constants.AddressZero);
        });
        
        it("Should prevent duplicate TLD names", async function () {
            const tldName = "eth";
            const registrationFee = ethers.utils.parseEther("0.01");
            const duration = 365 * 24 * 60 * 60;
            const tldFee = ethers.utils.parseEther("1000");
            
            // Create first TLD
            await tldFactory.connect(user1).createTLD(
                tldName,
                registrationFee,
                duration,
                { value: tldFee }
            );
            
            // Try to create duplicate
            await expect(
                tldFactory.connect(user2).createTLD(
                    tldName,
                    registrationFee,
                    duration,
                    { value: tldFee }
                )
            ).to.be.revertedWith("Name unavailable");
        });
    });
    
    describe("TLD Renewal", function () {
        it("Should renew a TLD", async function () {
            // Create TLD first
            const tldName = "eth";
            const registrationFee = ethers.utils.parseEther("0.01");
            const duration = 365 * 24 * 60 * 60;
            const tldFee = ethers.utils.parseEther("1000");
            
            await tldFactory.connect(user1).createTLD(
                tldName,
                registrationFee,
                duration,
                { value: tldFee }
            );
            
            // Get initial expiration
            const tldBefore = await tldFactory.getTLDFull(1);
            const initialExpiry = tldBefore.expirationTime;
            
            // Renew for another year
            await expect(
                tldFactory.connect(user1).renewTLD(
                    1,
                    duration,
                    { value: tldFee }
                )
            ).to.emit(tldFactory, "TLDRenewed");
            
            // Verify expiration was extended
            const tldAfter = await tldFactory.getTLDFull(1);
            expect(tldAfter.expirationTime).to.be.gt(initialExpiry);
        });
        
        it("Should only allow owner to renew", async function () {
            // Create TLD
            const tldName = "eth";
            const registrationFee = ethers.utils.parseEther("0.01");
            const duration = 365 * 24 * 60 * 60;
            const tldFee = ethers.utils.parseEther("1000");
            
            await tldFactory.connect(user1).createTLD(
                tldName,
                registrationFee,
                duration,
                { value: tldFee }
            );
            
            // Try to renew as non-owner
            await expect(
                tldFactory.connect(user2).renewTLD(
                    1,
                    duration,
                    { value: tldFee }
                )
            ).to.be.revertedWith("Not TLD owner");
        });
    });
    
    describe("Revenue Distribution", function () {
        it("Should track revenue for TLD owner and protocol", async function () {
            // Create TLD
            const tldName = "eth";
            const registrationFee = ethers.utils.parseEther("0.01");
            const duration = 365 * 24 * 60 * 60;
            const tldFee = ethers.utils.parseEther("1000");
            
            await tldFactory.connect(user1).createTLD(
                tldName,
                registrationFee,
                duration,
                { value: tldFee }
            );
            
            // Check pending withdrawals
            const treasuryPending = await revenueModule.getPendingWithdrawal(treasury.address);
            expect(treasuryPending).to.equal(tldFee);
            
            // Treasury can withdraw
            const treasuryBalanceBefore = await treasury.getBalance();
            await revenueModule.connect(treasury).withdraw();
            const treasuryBalanceAfter = await treasury.getBalance();
            
            // Should have received the fee (minus gas)
            expect(treasuryBalanceAfter).to.be.gt(treasuryBalanceBefore);
        });
    });
    
    describe("TLD Transfer", function () {
        it("Should transfer TLD ownership via NFT transfer", async function () {
            // Create TLD
            const tldName = "eth";
            const registrationFee = ethers.utils.parseEther("0.01");
            const duration = 365 * 24 * 60 * 60;
            const tldFee = ethers.utils.parseEther("1000");
            
            await tldFactory.connect(user1).createTLD(
                tldName,
                registrationFee,
                duration,
                { value: tldFee }
            );
            
            // Transfer NFT
            await tldFactory.connect(user1).transferFrom(
                user1.address,
                user2.address,
                1
            );
            
            // Verify new owner
            expect(await tldFactory.ownerOf(1)).to.equal(user2.address);
            
            // Verify TLD owner was updated
            const tld = await tldFactory.getTLDFull(1);
            expect(tld.owner).to.equal(user2.address);
        });
    });
    
    describe("Reserved TLDs", function () {
        it("Should allow owner to reserve TLDs", async function () {
            const tldName = "reserved";
            
            // Reserve TLD for user2
            await tldFactory.connect(owner).reserveTLD(tldName, user2.address);
            
            // User1 should not be able to create it
            await expect(
                tldFactory.connect(user1).createTLD(
                    tldName,
                    ethers.utils.parseEther("0.01"),
                    365 * 24 * 60 * 60,
                    { value: ethers.utils.parseEther("1000") }
                )
            ).to.be.revertedWith("Name unavailable");
            
            // User2 should be able to claim it
            await expect(
                tldFactory.connect(user2).claimReservedTLD(
                    tldName,
                    ethers.utils.parseEther("0.01"),
                    365 * 24 * 60 * 60,
                    { value: ethers.utils.parseEther("1000") }
                )
            ).to.emit(tldFactory, "TLDCreated");
            
            // Verify TLD was created for user2
            const tld = await tldFactory.getTLDFull(1);
            expect(tld.name).to.equal(tldName);
            expect(tld.owner).to.equal(user2.address);
        });
    });
    
    describe("System Health Check", function () {
        it("Should have all modules properly connected", async function () {
            // Verify storage module connections
            expect(await storageModule.authorized(await tldFactory.getAddress())).to.be.true;
            expect(await storageModule.authorized(await auctionModule.getAddress())).to.be.true;
            expect(await storageModule.authorized(await revenueModule.getAddress())).to.be.true;
            
            // Verify factory connections
            expect(await auctionModule.factory()).to.equal(await tldFactory.getAddress());
            expect(await revenueModule.factory()).to.equal(await tldFactory.getAddress());
            expect(await registrarFactory.tldFactory()).to.equal(await tldFactory.getAddress());
            
            // Verify treasury
            expect(await revenueModule.protocolTreasury()).to.equal(treasury.address);
        });
    });
});