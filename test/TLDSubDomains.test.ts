import { ethers, upgrades } from "hardhat";
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
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { expect } from "chai";
import { ZeroHash } from "ethers";

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
  deployer: HardhatEthersSigner,
  controller: HardhatEthersSigner;

describe("TLD Subdomains", async function () {
  before(async function () {
    console.log("Setting up TLD system...");

    // Get signers
    signers = await ethers.getSigners();
    owner = signers[0];
    user1 = signers[1];
    user2 = signers[2];
    treasury = signers[3];
    deployer = signers[4];
    controller = signers[5];

    console.log(ethers.namehash("Orbit"));
    //
    // Deploy Core
    //

    const OrbitRootFactory = await ethers.getContractFactory(
      "OrbitRoot",
      deployer
    );
    contracts.orbitRoot = (await OrbitRootFactory.deploy()) as OrbitRoot;

    const BlocklistFactory = await ethers.getContractFactory(
      "Blocklist",
      deployer
    );
    contracts.Blocklist = (await BlocklistFactory.deploy()) as Blocklist;
    await contracts.Blocklist.initialize();

    //
    // Storage
    //

    const TLDStorageFactory = await ethers.getContractFactory(
      "TLDStorage",
      deployer
    );
    contracts.storage = await upgrades.deployProxy(TLDStorageFactory, [], {
      initializer: "initialize",
      kind: "uups",
    });

    //
    // Auction
    //

    const TLDAuctionFactory = await ethers.getContractFactory(
      "TLDAuctionModule",
      deployer
    );
    contracts.auction = await upgrades.deployProxy(
      TLDAuctionFactory,
      [await contracts.storage.getAddress()],
      { initializer: "initialize", kind: "uups" }
    );

    //
    // Revenue
    //

    const TLDRevenueFactory = await ethers.getContractFactory(
      "TLDRevenueModule",
      deployer
    );

    contracts.revenue = await upgrades.deployProxy(
      TLDRevenueFactory,
      [
        await contracts.storage.getAddress(),
        await contracts.auction.getAddress(),
      ],
      { initializer: "initialize", kind: "uups" }
    );

    //
    // RegistrarFactory
    //

    const TLDRegistrarFactory = await ethers.getContractFactory(
      "TLDRegistrarFactory",
      deployer
    );
    contracts.registrarFactory = await upgrades.deployProxy(
      TLDRegistrarFactory,
      [
        await contracts.orbitRoot.orbit(),
        await contracts.orbitRoot.getAddress(),
      ],
      { initializer: "initialize", kind: "uups" }
    );

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

    console.log("✅ System deployed and configured");

    console.log("DeployedContracts", {
      Blocklist: await contracts.Blocklist.getAddress(),
      storage: await contracts.storage.getAddress(),
      auction: await contracts.auction.getAddress(),
      revenue: await contracts.revenue.getAddress(),
      registrarFactory: await contracts.registrarFactory.getAddress(),
      factory: await contracts.factory.getAddress(),
      orbitRoot: await contracts.orbitRoot.getAddress(),
    });
  });

  it(`Should deploy a TLD named Jug`, async function () {
    console.log("User1 ", user1.address);
    const tldName = "jug";
    const regFee = ethers.parseEther("1");
    const duration = 365 * 24 * 60 * 60; // 1 year

    const tx = await contracts.factory
      ?.connect(user1)
      .createTLD(tldName, regFee, duration, { value: regFee });

    const receipt = await tx?.wait();
    //console.log(receipt);

    // Check event was emitted
    const events = receipt?.logs.filter((log: any) => {
      try {
        return contracts.factory.interface.parseLog(log)?.name === "TLDCreated";
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

  it(`Should register a subdomain`, async function () {
    console.log("Initialting subdomain registration..");

    const tldData0 = await contracts.storage.getTLD(0);
    console.log("Token id 0", tldData0);
    const tldData = await contracts.storage.getTLD(1);
    console.log("Token id 1", tldData);

    console.log("Jug Registrar", tldData.registrar);

    const subdomainName = "Miner";
    const duration = 365 * 24 * 60 * 60; // 1 year

    const JugRegistrar = await ethers.getContractAt(
      "TLDRegistrar",
      tldData.registrar
    );

    const fees = await JugRegistrar.connect(user2).calculateFee(
      subdomainName,
      duration,
      user2.address
    );

    console.log(ethers.formatEther(fees), "fees");

    const tx2 = await JugRegistrar.connect(user2).registerDomain(
      subdomainName,
      user2.address,
      duration,
      { value: fees }
    );

    console.log(tx2);
  });
});
