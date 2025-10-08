import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { expect } from "chai";
import hre, { ethers, upgrades } from "hardhat";
import deployments from "../deployments/deployment-31337-1758887538400.json";
import {
  OrbitRegistry,
  OrbitRoot,
  Blocklist,
  TLDStorage,
  TLDAuctionModule,
  TLDRevenueModule,
  TLDRegistrarFactory,
  TLDFactory,
  TLDStorage__factory,
} from "../typechain-types";

type Contracts = {
  OrbitRegistry: OrbitRegistry;
  Blocklist: Blocklist;
  storage: TLDStorage;
  auction: TLDAuctionModule;
  revenue: TLDRevenueModule;
  registrarFactory: TLDRegistrarFactory;
  factory: TLDFactory;
  orbitRoot: OrbitRoot;
};

let contracts = {} as Contracts;
let signers = new Array<HardhatEthersSigner>();
let owner: HardhatEthersSigner,
  user1: HardhatEthersSigner,
  user2: HardhatEthersSigner,
  treasury: HardhatEthersSigner,
  deployer: HardhatEthersSigner;

describe("TLD Complete System Test", function () {
  before(async function () {
    console.log("Setting up TLD system...");

    // Get signers
    signers = await ethers.getSigners();
    owner = signers[0];
    user1 = signers[1];
    user2 = signers[2];
    treasury = signers[3];
    deployer = signers[4];

    console.log(ethers.namehash("Orbit"));
    //
    // Deploy Core
    //
    const OrbitRegistryFactory = await ethers.getContractFactory(
      "OrbitRegistry",
      deployer
    );
    contracts.OrbitRegistry = (await OrbitRegistryFactory.deploy(
      ethers.namehash("Orbit")
    )) as OrbitRegistry;

    const OrbitRootFactory = await ethers.getContractFactory(
      "OrbitRoot",
      deployer
    );
    contracts.orbitRoot = (await OrbitRootFactory.deploy(
      await contracts.OrbitRegistry.getAddress(),
      ethers.namehash("Orbit")
    )) as OrbitRoot;

    const BlocklistFactory = await ethers.getContractFactory(
      "Blocklist",
      deployer
    );
    contracts.Blocklist = (await BlocklistFactory.deploy()) as Blocklist;
    await contracts.Blocklist.initialize();

    //
    // Deploy Modules
    //
    const TLDStorageFactory = await ethers.getContractFactory(
      "TLDStorage",
      deployer
    );
    contracts.storage = (await TLDStorageFactory.deploy()) as TLDStorage;

    const TLDAuctionFactory = await ethers.getContractFactory(
      "TLDAuctionModule",
      deployer
    );
    contracts.auction = (await TLDAuctionFactory.deploy(
      await contracts.storage.getAddress()
    )) as TLDAuctionModule;

    const TLDRevenueFactory = await ethers.getContractFactory(
      "TLDRevenueModule",
      deployer
    );
    contracts.revenue = (await TLDRevenueFactory.deploy(
      await contracts.storage.getAddress(),
      treasury.address
    )) as TLDRevenueModule;

    const TLDRegistrarFactory = await ethers.getContractFactory(
      "TLDRegistrarFactory",
      deployer
    );
    contracts.registrarFactory = (await TLDRegistrarFactory.deploy(
      await contracts.OrbitRegistry.getAddress(),
      await contracts.orbitRoot.getAddress()
    )) as TLDRegistrarFactory;

    // //
    // // Deploy Main Factory
    // //
    const TLDFactoryFactory = await ethers.getContractFactory(
      "TLDFactory",
      deployer
    );
    contracts.factory = await upgrades.deployProxy(
      TLDFactoryFactory,
      [
        await contracts.storage.getAddress(),
        await contracts.auction.getAddress(),
        await contracts.revenue.getAddress(),
        await contracts.registrarFactory.getAddress(),
      ],
      { initializer: "initialize", kind: "uups" }
    );

    //
    // Configure Access
    //
    const factoryAddr = await contracts.factory.getAddress();
    console.log("Factory Address", factoryAddr);

    await contracts.storage!.authorize(factoryAddr);
    await contracts.storage!.authorize(await contracts.auction!.getAddress());
    await contracts.storage!.authorize(await contracts.revenue!.getAddress());
    await contracts.storage.authorize(
      await contracts.registrarFactory.getAddress()
    );

    await contracts.auction!.setFactory(factoryAddr);
    await contracts.revenue!.setFactory(factoryAddr);
    await contracts.registrarFactory!.setTLDFactory(factoryAddr);

    await contracts.orbitRoot.setController(
      await contracts.registrarFactory.getAddress(),
      true
    );

    await contracts.OrbitRegistry.setOwner(
      ethers.namehash("Orbit"),
      await contracts.orbitRoot.getAddress()
    );
    console.log("✅ System deployed and configured");

    console.log("DeployedContracts", {
      OrbitRegistry: await contracts.OrbitRegistry.getAddress(),
      Blocklist: await contracts.Blocklist.getAddress(),
      storage: await contracts.storage.getAddress(),
      auction: await contracts.auction.getAddress(),
      revenue: await contracts.revenue.getAddress(),
      registrarFactory: await contracts.registrarFactory.getAddress(),
      factory: await contracts.factory.getAddress(),
      orbitRoot: await contracts.orbitRoot.getAddress(),
    });
  });

  describe("Access test", function () {
    it("Should check access for TLDFactory in TLDRegistrarFactory", async function () {
      expect(await contracts.registrarFactory.tldFactory()).to.equal(
        await contracts.factory.getAddress()
      );
    });
    it("Should check access for factory in revenue module", async function () {
      expect(await contracts.revenue.factory()).to.equal(
        await contracts.factory.getAddress()
      );
    });

    it("Should check access for factory in auction module", async function () {
      expect(await contracts.auction.factory()).to.equal(
        await contracts.factory.getAddress()
      );
    });

    it("Should Check Registrar authorized in Storage Module", async function () {
      expect(
        await contracts.storage.authorized(
          await contracts.registrarFactory.getAddress()
        )
      ).to.be.true;
    });
  });

  describe("TLD Creation", function () {
    it(`Should create a TLD successfully`, async function () {
      console.log("User1 ", user1.address);
      const tldName = "eth";
      const regFee = ethers.parseEther("1");
      const duration = 365 * 24 * 60 * 60; // 1 year

      const tx = await contracts.factory
        ?.connect(user1)
        .createTLD(tldName, regFee, duration, { value: regFee });

      const receipt = await tx?.wait();
      console.log(receipt);

      // Check event was emitted
      const events = receipt?.logs.filter((log: any) => {
        try {
          return (
            contracts.factory.interface.parseLog(log)?.name === "TLDCreated"
          );
        } catch {
          return false;
        }
      });
      expect(events?.length).to.equal(1);

      // Verify TLD data
      // Exception for now since tracer is enabled
      const tld = await contracts.storage.getTLD(1);

      expect(ethers.decodeBytes32String(tld.name)).to.equal(tldName);
      expect(tld.owner).to.equal(user1.address);
      expect(tld.registrationFee).to.equal(regFee);
      expect(tld.isActive).to.be.true;

      // Verify NFT ownership
      expect(await contracts.factory.ownerOf(1)).to.equal(user1.address);

      console.log("    ✅ TLD 'eth' created successfully");
    });

    it("Should prevent duplicate TLD names", async function () {
      await expect(
        contracts.factory.connect(user2).createTLD(
          "eth", // Same name
          ethers.parseEther("0.02"),
          365 * 24 * 60 * 60,
          { value: ethers.parseEther("1000") }
        )
      ).to.be.revertedWith("Taken");

      console.log("    ✅ Duplicate prevention working");
    });

    it("Should create multiple unique TLDs", async function () {
      await contracts.factory
        .connect(user2)
        .createTLD("btc", ethers.parseEther("0.015"), 365 * 24 * 60 * 60, {
          value: ethers.parseEther("1000"),
        });

      const tld = await contracts.storage.getTLD(2);
      expect(ethers.decodeBytes32String(tld.name)).to.equal("btc");
      expect(tld.owner).to.equal(user2.address);

      console.log("    ✅ Multiple TLDs working");
    });
  });

  describe("TLD Renewal", function () {
    it("Should renew a TLD", async function () {
      const tldBefore = await contracts.storage.getTLD(1);
      const initialExpiry = tldBefore.expirationTime;

      await contracts.factory.connect(user1).renewTLD(
        1,
        365 * 24 * 60 * 60, // 1 more year
        { value: ethers.parseEther("1") }
      );

      const tldAfter = await contracts.storage.getTLD(1);
      expect(tldAfter.expirationTime).to.be.gt(initialExpiry);

      console.log("    ✅ TLD renewal working");
    });

    it("Should only allow owner to renew", async function () {
      await expect(
        contracts.factory.connect(user2).renewTLD(
          1, // User1's TLD
          365 * 24 * 60 * 60,
          { value: ethers.parseEther("1000") }
        )
      ).to.be.revertedWith("Not owner");

      console.log("    ✅ Ownership check working");
    });
  });

  describe("Revenue Distribution", function () {
    it("Should distribute creation fees to treasury", async function () {
      const pending = await contracts.revenue.getPendingWithdrawal(
        treasury.address
      );
      expect(pending).to.be.gt(0);

      const balanceBefore = await ethers.provider.getBalance(treasury.address);
      await contracts.revenue.connect(treasury).withdraw();
      const balanceAfter = await ethers.provider.getBalance(treasury.address);

      expect(balanceAfter).to.be.gt(balanceBefore);

      console.log("    ✅ Revenue distribution working");
    });
  });

  describe("TLD Transfer", function () {
    it("Should transfer TLD via NFT transfer", async function () {
      const owner = await contracts.factory.owner();

      const registrarAddress = await contracts.registrarFactory.getRegistrar(1);

      const Registrar = await ethers.getContractAt(
        "TLDRegistrar",
        registrarAddress
      );

      console.log("Registrar:", registrarAddress);

      console.log("Owner:", await Registrar.owner());

      await contracts.factory
        .connect(user1)
        .transferFrom(user1.address, user2.address, 1);

      expect(await contracts.factory.ownerOf(1)).to.equal(user2.address);

      const tld = await contracts.factory.getTLD(1);
      expect(tld.owner).to.equal(user2.address);

      console.log("    ✅ TLD transfer working");
    });
  });

  describe("Auction System", function () {
    it("Should start auction for expired TLD", async function () {
      // Fast forward time to expire TLD
      const tld = await contracts.storage.getTLD(2);
      const expiry = Number(tld.expirationTime) + 31 * 24 * 60 * 60; // Past grace period

      await ethers.provider.send("evm_setNextBlockTimestamp", [expiry]);
      await ethers.provider.send("evm_mine");

      await contracts.factory.checkExpiry(2);

      const updatedTld = await contracts.storage.getTLD(2);
      expect(updatedTld.isActive).to.be.false;

      console.log("    ✅ Expiration and auction start working");
    });

    it("Should allow bidding on expired TLD", async function () {
      await contracts.factory
        .connect(user1)
        .bid(2, { value: ethers.parseEther("1500") });

      const auction = await contracts.auction.getAuction(2);
      expect(auction.currentBidder).to.equal(user1.address);

      console.log("    ✅ Auction bidding working");
    });
  });

  describe("System Integration", function () {
    it("Should have all modules properly connected", async function () {
      const factoryAddr =
        contracts.factory.target || (await contracts.factory.getAddress());

      expect(await contracts.storage.authorized(factoryAddr)).to.be.true;
      expect(await contracts.auction.factory()).to.equal(factoryAddr);
      expect(await contracts.revenue.factory()).to.equal(factoryAddr);
      expect(await contracts.registrarFactory.tldFactory()).to.equal(
        factoryAddr
      );

      console.log("    ✅ All modules connected correctly");
    });

    it("Should track total TLDs created", async function () {
      const totalSupply = await contracts.factory.totalSupply();
      expect(totalSupply).to.be.gt(0);

      console.log("✅ NFT tracking working");
    });
  });

  describe("Gas Usage", function () {
    it("Should have reasonable gas costs", async function () {
      const tx = await contracts.factory
        .connect(owner)
        .createTLD("gas", ethers.parseEther("0.01"), 365 * 24 * 60 * 60, {
          value: ethers.parseEther("1"),
        });

      const receipt = await tx.wait();
      const gasUsed = receipt?.gasUsed;

      console.log(`    ⛽ TLD creation gas: ${gasUsed?.toString()}`);
      expect(gasUsed).to.be.lt(5000000); // Should be under 5M gas
    });
  });
});

// Run with: npx hardhat test test/TLDComplete.test.js
