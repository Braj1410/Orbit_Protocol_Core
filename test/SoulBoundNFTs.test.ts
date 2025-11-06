import { expect } from "chai";
import { ethers, upgrades } from "hardhat";
import {
  OrbitRegistry,
  PublicResolver,
  SoulboundRegistrar,
} from "../typechain-types";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { namehash } from "ethers";

describe("SoulboundRegistrar", function () {
  let owner: HardhatEthersSigner,
    user1: HardhatEthersSigner,
    user2: HardhatEthersSigner,
    verifier: HardhatEthersSigner,
    controller: HardhatEthersSigner;
  let registrar: SoulboundRegistrar,
    orbit: OrbitRegistry,
    resolver: PublicResolver;

  beforeEach(async () => {
    [owner, user1, user2, verifier, controller] = await ethers.getSigners();

    const OrbitRootFactory = await ethers.getContractFactory(
      "OrbitRoot",
      owner
    );
    const orbitRoot = await OrbitRootFactory.deploy();

    const OrbitRegistrarAddr = await orbitRoot.orbit();

    orbit = await ethers.getContractAt(
      "OrbitRegistry",
      OrbitRegistrarAddr,
      owner
    );

    const Registrar = await ethers.getContractFactory("SoulboundRegistrar");
    registrar = await upgrades.deployProxy(
      Registrar,
      [orbit.target, namehash("soulbound")],
      { kind: "uups" }
    );
    await registrar.waitForDeployment();

    await orbitRoot.setController(owner.address, true);
    // Register base node for soulbound domains
    await orbitRoot.registerNode(namehash("soulbound"), registrar.target);

    // Deploy Public Resolver
    const PublicResolverFactory = await ethers.getContractFactory(
      "PublicResolver",
      owner
    );
    resolver = await PublicResolverFactory.deploy(orbit.target);
    await resolver.waitForDeployment();

    // Assign roles
    await registrar.connect(owner).setController(controller.address, true);
    await registrar.connect(owner).setVerifier(verifier.address, true);
  });

  it("should mint a soulbound domain", async () => {
    const tx = await registrar
      .connect(controller)
      .mintSoulbound("alice", user1.address, resolver.target);

    const tokenId = await registrar.tokenByOwner(user1.address);
    expect(await registrar.ownerOf(tokenId)).to.equal(user1.address);

    const metadata = await registrar.getMetadata(tokenId);
    expect(metadata.name).to.equal("alice");
    expect(metadata.isActive).to.equal(true);

    const labelHash = ethers.keccak256(ethers.toUtf8Bytes("alice"));
    console.log("Label Hash:", labelHash);
    const node = namehash("alice.soulbound");
    console.log("Node:", node);
    expect(await orbit.owner(node)).to.equal(user1.address);
  });

  it("should not allow transfer", async () => {
    await registrar
      .connect(controller)
      .mintSoulbound("bobby", user2.address, ethers.ZeroAddress);

    const tokenId = await registrar.tokenByOwner(user2.address);

    await expect(
      registrar
        .connect(user2)
        .transferFrom(user2.address, user1.address, tokenId)
    ).to.be.revertedWith("Soulbound: transfers disabled");
  });

  it("should update reputation", async () => {
    await registrar
      .connect(controller)
      .mintSoulbound("alice", user1.address, ethers.ZeroAddress);
    const tokenId = await registrar.tokenByOwner(user1.address);

    await registrar
      .connect(controller)
      .incrementReputation(tokenId, 50, "Test boost");
    let rep = await registrar.getReputation(tokenId);
    expect(rep).to.equal(150);

    await registrar
      .connect(controller)
      .decrementReputation(tokenId, 100, "Test penalty");
    rep = await registrar.getReputation(tokenId);
    expect(rep).to.equal(50);
  });

  it("should add verification badge", async () => {
    await registrar
      .connect(controller)
      .mintSoulbound("bob", user2.address, ethers.ZeroAddress);

    const tokenId = await registrar.tokenByOwner(user2.address);
    await registrar.connect(verifier).addVerification(tokenId, "Twitter", "0x");

    expect(await registrar.hasVerification(tokenId, "Twitter")).to.be.true;

    const all = await registrar.getVerifications(tokenId);
    expect(all[0]).to.equal("Twitter");
  });
  it("should allow owner to burn their domain", async () => {
    await registrar
      .connect(controller)
      .mintSoulbound("bob", user2.address, ethers.ZeroAddress);

    const tokenId = await registrar.tokenByOwner(user2.address);
    await registrar.connect(user2).burnSoulbound(tokenId);

    await expect(registrar.ownerOf(tokenId)).to.be.reverted;
    const meta = await registrar.getMetadata(tokenId).catch(() => null);
    expect(meta).to.be.null;
  });
  it("should allow recovery after delay", async () => {
    await registrar
      .connect(controller)
      .mintSoulbound("charlie", user1.address, ethers.ZeroAddress);

    const tokenId = await registrar.tokenByOwner(user1.address);

    await registrar.connect(owner).initiateRecovery(tokenId, user2.address);

    // Increase time by 7 days
    await ethers.provider.send("evm_increaseTime", [7 * 24 * 60 * 60]);
    await ethers.provider.send("evm_mine");

    await registrar.connect(owner).completeRecovery(tokenId);

    expect(await registrar.ownerOf(tokenId)).to.equal(user2.address);
  });
  it("should prevent same owner from minting twice", async () => {
    await registrar
      .connect(controller)
      .mintSoulbound("dave", user1.address, ethers.ZeroAddress);

    await expect(
      registrar
        .connect(controller)
        .mintSoulbound("another", user1.address, ethers.ZeroAddress)
    ).to.be.revertedWith("Already has soulbound domain");
  });
});
