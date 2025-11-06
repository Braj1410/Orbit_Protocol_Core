import { expect } from "chai";
import { ethers, upgrades } from "hardhat";
import { OfficialBadgeRegistry, OrbitRegistry } from "../typechain-types";
import { namehash } from "ethers";

describe("OfficialBadgeRegistry", function () {
  let registry: OfficialBadgeRegistry;
  let orbit: OrbitRegistry;
  let owner: any;
  let user1: any;
  let user2: any;
  let kycNode: string;
  let officialNode: string;

  beforeEach(async function () {
    [owner, user1, user2] = await ethers.getSigners();

    // Deploy Orbit mock
    const OrbitRoot = await ethers.getContractFactory("OrbitRoot");

    const orbitRoot = await OrbitRoot.deploy();
    await orbitRoot.waitForDeployment();

    const OrbitAddr = await orbitRoot.orbit();
    orbit = await ethers.getContractAt("OrbitRegistry", OrbitAddr, owner);

    // Compute fake nodes
    kycNode = namehash("kyc");
    officialNode = namehash("official");

    await orbitRoot.setController(owner.address, true);

    // Deploy OfficialBadgeRegistry (UUPS)
    const BadgeRegistry = await ethers.getContractFactory(
      "OfficialBadgeRegistry"
    );
    registry = await upgrades.deployProxy(
      BadgeRegistry,
      [orbit.target, kycNode, officialNode],
      { kind: "uups", initializer: "initialize" }
    );
    await registry.waitForDeployment();

    await orbitRoot.registerNode(kycNode, registry.target);
    await orbitRoot.registerNode(officialNode, registry.target);
  });

  it("should initialize properly", async () => {
    expect(await registry.owner()).to.equal(owner.address);
    expect(await registry.kycNode()).to.equal(kycNode);
    expect(await registry.officialNode()).to.equal(officialNode);
  });

  it("should issue a badge", async () => {
    const tx = await registry.issueBadge(
      user1.address,
      1, // OFFICIAL_TEAM
      "OrbitLabs",
      "Developer",
      '{"skills":"Solidity"}',
      0
    );
    const receipt = await tx.wait();

    const event = receipt?.logs.find(
      (log: any) => log.fragment?.name === "BadgeIssued"
    );
    expect(event).to.exist;

    const badgeId = await registry.getBadges(user1.address);
    expect(badgeId.length).to.equal(1);

    const badge = await registry.badges(badgeId[0]);
    expect(badge.organization).to.equal("OrbitLabs");
    expect(badge.role).to.equal("Developer");
    expect(await registry.ownerOf(badgeId[0])).to.equal(user1.address);
  });

  it("should issue a KYC badge and store KYC data", async () => {
    const kycHash = ethers.keccak256(ethers.toUtf8Bytes("kyc-docs"));

    const tx = await registry.issueKYCBadge(
      user2.address,
      kycHash,
      "ChainKYC",
      2,
      "IN"
    );
    await tx.wait();

    const badges = await registry.getBadges(user2.address);
    const badgeId = badges[0];

    const badge = await registry.badges(badgeId);
    expect(badge.badgeType).to.equal(0); // KYC_VERIFIED
    const kycData = await registry.kycData(badgeId);
    expect(kycData.provider).to.equal("ChainKYC");
    expect(kycData.country).to.equal("IN");
    expect(await registry.getKYCLevel(user2.address)).to.equal(2);
  });

  it("should prevent transfers (soulbound)", async () => {
    const badgeId = await registry
      .issueBadge(user1.address, 1, "Orbit", "Dev", "", 0)
      .then(async (tx: any) => {
        const rec = await tx.wait();
        const badgeIds = await registry.getBadges(user1.address);
        return badgeIds[0];
      });

    await expect(
      registry
        .connect(user1)
        .transferFrom(user1.address, user2.address, badgeId)
    ).to.be.revertedWith("Badges are soulbound and cannot be transferred");
  });

  it("should revoke badge", async () => {
    const badgeId = await registry
      .issueBadge(user1.address, 1, "Orbit", "Lead", "", 0)
      .then(async (tx: any) => {
        const rec = await tx.wait();
        const ids = await registry.getBadges(user1.address);
        return ids[0];
      });

    await registry.revokeBadge(badgeId, "Violation");

    const badge = await registry.badges(badgeId);
    expect(badge.isActive).to.be.false;
  });

  it("should update badge metadata", async () => {
    const badgeId = await registry
      .issueBadge(user1.address, 1, "Orbit", "Engineer", "", 0)
      .then(async (tx: any) => {
        const rec = await tx.wait();
        const ids = await registry.getBadges(user1.address);
        return ids[0];
      });

    await registry.updateBadgeMetadata(badgeId, '{"level":"senior"}');
    const badge = await registry.badges(badgeId);
    expect(badge.metadata).to.equal('{"level":"senior"}');
  });

  it("should return active badges only", async () => {
    const id1 = await registry
      .issueBadge(user1.address, 1, "Org", "Dev", "", 0)
      .then(async (tx: any) => (await registry.getBadges(user1.address))[0]);
    const id2 = await registry
      .issueBadge(user1.address, 1, "Org", "Mgr", "", 0)
      .then(async (tx: any) => (await registry.getBadges(user1.address))[1]);

    await registry.revokeBadge(id1, "Revoked");

    const activeBadges = await registry.getActiveBadges(user1.address);
    expect(activeBadges.length).to.equal(1);
    expect(activeBadges[0]).to.equal(id2);
  });
});
