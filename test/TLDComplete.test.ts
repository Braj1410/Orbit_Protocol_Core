import { ethers, network, upgrades } from "hardhat";

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
  PublicResolver,
  ReverseRegistrar,
  UniversalReverseAdapter,
  OrbitPriceOracle,
} from "../typechain-types";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { expect, use } from "chai";
import {
  Contract,
  EnsPlugin,
  EnsResolver,
  getAddress,
  namehash,
  randomBytes,
  resolveAddress,
  ZeroAddress,
  ZeroHash,
} from "ethers";
import { get } from "http";
import { reverse } from "dns";
import { getProvider } from "./utils/NativeEthers";

const RPCURL = "https://localhost:8545/";
type Contracts = {
  priceOracle: OrbitPriceOracle;

  Blocklist: Blocklist;
  storage: TLDStorage;
  auction: TLDAuctionModule;
  revenue: TLDRevenueModule;
  registrarFactory: TLDRegistrarFactory;
  factory: TLDFactory;
  orbitRoot: OrbitRoot;
  publicResolver: PublicResolver;
  reverseRegistrar: ReverseRegistrar;
  orbitRegistry: OrbitRegistry;
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
    // // Deploy Public Resolver
    // //

    const PublicResolverFactory = await ethers.getContractFactory(
      "PublicResolver",
      deployer
    );
    contracts.publicResolver = (await PublicResolverFactory.deploy(
      await contracts.orbitRoot.orbit()
    )) as PublicResolver;

    // //
    // // Deploy Reverse Resolver
    // //

    const ReverseResolverFactory = await ethers.getContractFactory(
      "ReverseRegistrar",
      deployer
    );
    contracts.reverseRegistrar = (await upgrades.deployProxy(
      ReverseResolverFactory,
      [await contracts.orbitRoot.orbit()],
      { initializer: "initialize", kind: "uups" }
    )) as ReverseRegistrar;

    const PriceOracleFactory = await ethers.getContractFactory(
      "OrbitPriceOracle",
      deployer
    );
    contracts.priceOracle = (await upgrades.deployProxy(PriceOracleFactory, [
      ethers.parseEther("100"),
      ethers.parseEther("10"),
      ethers.parseEther("1"),
      ethers.parseEther("0.1"),
      ethers.parseEther("0.01"),
      false,
    ])) as OrbitPriceOracle;

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
        await contracts.publicResolver.getAddress(),
        await contracts.reverseRegistrar.getAddress(),
        await contracts.priceOracle.getAddress(),
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

    await contracts.orbitRoot.setController(deployer.address, true);

    await contracts.orbitRoot.registerNode(
      "0x91d1777781884d03a6757a803996e38de2a42967fb37eeaca72729271025a9e2",
      await contracts.reverseRegistrar.getAddress()
    );

    const orbitRegistryAddr = await contracts.orbitRoot.orbit();

    contracts.orbitRegistry = await ethers.getContractAt(
      "OrbitRegistry",
      orbitRegistryAddr
    );

    console.log("✅ System deployed and configured");

    console.log("DeployedContracts", {
      Blocklist: await contracts.Blocklist.getAddress(),
      storage: await contracts.storage.getAddress(),
      auction: await contracts.auction.getAddress(),
      revenue: await contracts.revenue.getAddress(),
      registrarFactory: await contracts.registrarFactory.getAddress(),
      factory: await contracts.factory.getAddress(),
      orbitRegistry: await contracts.orbitRoot.orbit(),
      orbitRoot: await contracts.orbitRoot.getAddress(),
      publicResolver: await contracts.publicResolver.getAddress(),
      reverseRegistrar: await contracts.reverseRegistrar.getAddress(),
    });

    console.log("Users", {
      owner: owner.address,
      user1: user1.address,
      user2: user2.address,
      treasury: treasury.address,
      deployer: deployer.address,
      controller: controller.address,
    });
  });

  describe("TLD Creation", function () {
    let deployedController: string;
    it(`Should create a TLD successfully`, async function () {
      console.log("User1 ", user1.address);
      const tldName = "eth";
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

      console.log("✅ TLD 'eth' created successfully");
    });

    it("Should deploy controller and set controller to registrar", async function () {
      const controller = await ethers.getContractFactory(
        "OrbitRegistrarController",
        user1
      );
      const tld = await contracts.storage.getTLD(1);
      const TLDRegistrar = await ethers.getContractAt(
        "TLDRegistrar",
        tld.registrar
      );
      const controllerContract = await upgrades.deployProxy(controller, [
        tld.registrar,
        await contracts.priceOracle.getAddress(),
        await contracts.reverseRegistrar.getAddress(),
        await TLDRegistrar.baseNode(),
        "eth",
      ]);

      expect(await TLDRegistrar.baseNode()).to.equal(namehash("eth"));
      deployedController = await controllerContract.getAddress();
      console.log("Controller Address:", deployedController);
      console.log("✅ Controller deployed");

      await TLDRegistrar.connect(user1).addController(deployedController);
      console.log("✅ Controller set in Registrar");
      expect(await TLDRegistrar.controllers(deployedController)).to.be.true;
    });

    it("Should register a subdomain without reverse registrar", async function () {
      const controller = await ethers.getContractAt(
        "OrbitRegistrarController",
        deployedController,
        user2
      );

      const secret = randomBytes(32);

      const duration = BigInt(365 * 24 * 60 * 60); // 1 year

      const resolver = await contracts.publicResolver.getAddress();
      const reverseRegistrar = await contracts.reverseRegistrar.getAddress();

      const getCommitment = await controller.makeCommitment(
        "test2",
        user2.address,
        duration,
        secret,
        resolver,
        [],
        false
      );

      const makeCommitmenttx = await controller.commit(getCommitment);

      console.log("Commitment: ", getCommitment);

      const minimumCommitmentAge = await controller.minCommitmentAge();
      const maxCommitmentAge = await controller.maxCommitmentAge();

      const commitmentTimeStamp = await controller.commitments(getCommitment);
      console.log(commitmentTimeStamp.toString(), "commitment timestamp");

      const latestBlock = await ethers.provider.getBlock("latest");

      console.log(latestBlock?.timestamp, "latest block timestamp");
      console.log(minimumCommitmentAge.toString(), "minimum commitment age");

      //@ts-ignore
      const expiry = latestBlock.timestamp + 500;
      //@ts-ignore
      const contractExpiry = BigInt(latestBlock.timestamp) + maxCommitmentAge;

      console.log(expiry, "commitment expiry time");
      console.log(contractExpiry, "max commitment age time");
      await network.provider.send("evm_setNextBlockTimestamp", [expiry]);
      await network.provider.send("evm_mine");

      const getCost = await controller.getPrice("test", duration);

      const registertx = await controller.register(
        "test2",
        user2.address,
        duration,
        secret,
        resolver,
        [],
        false,
        {
          value: getCost,
        }
      );

      console.log(registertx);
    });
    it("Should revert when registering a subdomain with reverse registrar without user approval", async function () {
      const controller = await ethers.getContractAt(
        "OrbitRegistrarController",
        deployedController,
        user2
      );

      const secret = randomBytes(32);

      const duration = BigInt(365 * 24 * 60 * 60); // 1 year

      const resolver = await contracts.publicResolver.getAddress();
      const reverseRegistrar = await contracts.reverseRegistrar.getAddress();

      const getCommitment = await controller.makeCommitment(
        "test3",
        user2.address,
        duration,
        secret,
        resolver,
        [],
        true
      );

      const makeCommitmenttx = await controller.commit(getCommitment);

      console.log("Commitment: ", getCommitment);

      const minimumCommitmentAge = await controller.minCommitmentAge();

      const latestBlock = await ethers.provider.getBlock("latest");

      console.log(latestBlock?.timestamp, "latest block timestamp");
      console.log(minimumCommitmentAge.toString(), "minimum commitment age");

      //@ts-ignore
      const expiry = latestBlock.timestamp + 500;

      console.log(expiry, "commitment expiry time");
      await network.provider.send("evm_setNextBlockTimestamp", [expiry]);
      await network.provider.send("evm_mine");

      const getCost = await controller.getPrice("test", duration);

      await expect(
        controller.register(
          "test3",
          user2.address,
          duration,
          secret,
          resolver,
          [],
          true,
          {
            value: getCost,
          }
        )
      ).to.be.revertedWithoutReason();
    });
    it("Should not revert when registering a subdomain with reverse registrar with user approval", async function () {
      const controller = await ethers.getContractAt(
        "OrbitRegistrarController",
        deployedController,
        user2
      );

      const secret = randomBytes(32);

      const duration = BigInt(365 * 24 * 60 * 60); // 1 year

      const resolver = await contracts.publicResolver.getAddress();

      const orbitRegistry = await contracts.orbitRoot.orbit();

      const orbitRegistryContract = await ethers.getContractAt(
        "OrbitRegistry",
        orbitRegistry
      );

      // Set Approval for Reverse Registrar
      await orbitRegistryContract
        .connect(user2)
        .setApprovalForAll(await controller.getAddress(), true);

      await orbitRegistryContract
        .connect(user2)
        .setApprovalForAll(await contracts.reverseRegistrar.getAddress(), true);

      const getCommitment = await controller.makeCommitment(
        "test4",
        user2.address,
        duration,
        secret,
        resolver,
        [],
        true
      );

      const makeCommitmenttx = await controller.commit(getCommitment);

      console.log("Commitment: ", getCommitment);

      const minimumCommitmentAge = await controller.minCommitmentAge();

      const latestBlock = await ethers.provider.getBlock("latest");

      console.log(latestBlock?.timestamp, "latest block timestamp");
      console.log(minimumCommitmentAge.toString(), "minimum commitment age");

      //@ts-ignore
      const expiry = latestBlock.timestamp + 500;

      console.log(expiry, "commitment expiry time");
      await network.provider.send("evm_setNextBlockTimestamp", [expiry]);
      await network.provider.send("evm_mine");

      const getCost = await controller.getPrice("test", duration);

      const registertx = await controller.register(
        "test4",
        user2.address,
        duration,
        secret,
        resolver,
        [],
        true,
        {
          value: getCost,
        }
      );

      await orbitRegistryContract
        .connect(user2)
        .setResolver(namehash("test4.eth"), contracts.publicResolver.target);

      //console.log(registertx);
      // const reverseNode = ethers.namehash(
      //   `${user2.address.slice(2).toLowerCase()}.addr.reverse`
      // );
      // const orbitRegistryAddre = await contracts.orbitRoot.orbit();

      // const orbitRegistryContract2 = await ethers.getContractAt(
      //   "OrbitRegistry",
      //   orbitRegistryAddre
      // );

      // const name1 = await contracts.publicResolver.name(reverseNode);

      // expect(name1).to.equal("test4.eth");

      const hash = ethers.namehash("test4.eth");
      const setAddr = await contracts.publicResolver
        .connect(user2)
        ["setAddr(bytes32,address)"](hash, user2.address);
      // const addr = await contracts.publicResolver["addr(bytes32)"](hash);
      // expect(addr).to.equal(user2.address);

      const chainId = (await ethers.provider.getNetwork()).chainId;

      const networkP = network.config;
      const provider = getProvider(
        RPCURL,
        await contracts.orbitRegistry.getAddress(),
        chainId,
        "fg"
      );

      const ensAddr = await EnsResolver.getEnsAddress(provider);
      console.log("ENS Address: ", ensAddr);

      const ensContract = new Contract(
        ensAddr,
        ["function resolver(bytes32) view returns (address)"],
        provider
      );

      const addr = getAddress(user2.address);
      const node = namehash(addr.substring(2).toLowerCase() + ".addr.reverse");

      const resolver2 = await ensContract.resolver(node);
      console.log("Resolver from ENS: ", resolver2);

      const resolverContract = new Contract(
        resolver2,
        ["function name(bytes32) view returns (string)"],
        provider
      );
      const name3 = await resolverContract.name(node);

      console.log("Resolved name: ", name3);

      const res = await provider.getResolver(name3);

      if (res == null) {
        console.log("Resolver is null");
        return;
      }
      console.log(
        "Resolved name from provider: ",
        await GetAddress(resolver2, res)
      );

      const name = provider.lookupAddress(user2.address);
      console.log("Resolved name from provider: ", await name);
    });
  });
});

async function GetAddress(
  resolver_addr: string,
  Ens: EnsResolver,
  coinType?: number
): Promise<null | string> {
  if (coinType == null) {
    coinType = 60;
  }
  if (coinType === 60) {
    try {
      const con = new Contract(
        resolver_addr,
        [
          "function supportsInterface(bytes4) view returns (bool)",
          "function resolve(bytes, bytes) view returns (bytes)",
          "function addr(bytes32) view returns (address)",
          "function addr(bytes32, uint) view returns (bytes)",
          "function text(bytes32, string) view returns (string)",
          "function contenthash(bytes32) view returns (bytes)",
        ],
        Ens.provider
      );

      const result = await con["addr(bytes32)"](namehash(Ens.name));
      console.log("Address from addr(bytes32): ", result);
      // No address
      if (result == null || result === ZeroAddress) {
        return null;
      }

      return result;
    } catch (error: any) {
      throw error;
      return null;
    }
  }
  return null;
}
