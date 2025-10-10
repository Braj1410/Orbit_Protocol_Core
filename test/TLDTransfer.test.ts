import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { expect } from "chai";
import hre, { ethers, upgrades } from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";

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

async function deployContracts() {
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

  return { contracts };
}

describe("TLD Transfer", async function () {
  before(async function () {
    await deployContracts();
  });

  it("Should create a TLD", async function () {
    const tldName = "tear";
    const regFee = ethers.parseEther("1");
    const duration = 365 * 24 * 60 * 60; // 1 year

    const tx = await contracts.factory
      ?.connect(user1)
      .createTLD(tldName, regFee, duration, { value: regFee });

    const receipt = await tx?.wait();
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

    const Registrar = await ethers.getContractAt("TLDRegistrar", tld.registrar);

    expect(ethers.decodeBytes32String(tld.name)).to.equal(tldName);
    expect(tld.owner).to.equal(user1.address);
    expect(tld.registrationFee).to.equal(regFee);
    expect(tld.isActive).to.be.true;

    // Verify NFT ownership
    expect(await contracts.factory.ownerOf(1)).to.equal(user1.address);

    console.log("    ✅ TLD 'eth' created successfully");
  });
  it("Admin has NFT", async function () {
    const registrarData = await contracts.factory.getTLD(1);
    console.log("Registrar Address", registrarData.registrar);
    const Registrar = await ethers.getContractAt(
      "TLDRegistrar",
      registrarData.registrar
    );
    const tld = await contracts.storage.getTLD(1);
    expect(tld.owner).to.equal(user1.address);
  });

  it("Should transfer TLD via NFT transfer", async function () {
    const registrarData = await contracts.factory.getTLD(1);
    console.log("Registrar Address", registrarData.registrar);
    const Registrar = await ethers.getContractAt(
      "TLDRegistrar",
      registrarData.registrar
    );

    const tld = await contracts.storage.getTLD(1);
    expect(tld.owner).to.equal(user1.address);
    await contracts.factory
      .connect(user1)
      .transferFrom(user1.address, user2.address, 1);
    expect(await contracts.factory.ownerOf(1)).to.equal(user2.address);
    console.log("    ✅ TLD ownership transferred successfully");
  });
});
