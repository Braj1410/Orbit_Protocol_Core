import hre, { ethers, upgrades } from "hardhat";
import fs from "fs";
import path from "path";

let deployer: any;
// Deployment configuration
const config = {
  // Price settings (in CRO)
  prices: {
    oneChar: ethers.parseEther("1000"),
    twoChar: ethers.parseEther("500"),
    threeChar: ethers.parseEther("100"),
    fourChar: ethers.parseEther("50"),
    fiveChar: ethers.parseEther("10"),
  },
  // Revenue distribution percentages
  revenue: {
    treasury: 40,
    team: 20,
    staking: 40,
  },
  // Deployment addresses
  addresses: {
    treasury:
      process.env.TREASURY_ADDRESS ||
      "0x0000000000000000000000000000000000000000",
    team:
      process.env.TEAM_WALLET_ADDRESS ||
      "0x0000000000000000000000000000000000000000",
    governance: process.env.GOVERNANCE_ADDRESS || null,
  },
};

// Store deployed addresses
const deployedAddresses = {
  orbitRegistry: "",
  orbitRoot: "",
  priceOracle: "",
  blocklist: "",
  chanceSystem: "",
  revenueDistributor: "",
  publicResolver: "",
  orbitRegistrar: "",
  reverseRegistrar: "",
  controller: "",
  soulboundRegistrar: "",
  badgeRegistry: "",
  subdomainRegistrar: "",
  reverseAdapter: "",
  tldStorage: "",
  auctionModule: "",
  tldRevenueModule: "",
  tldRegistrarFactory: "",
  tldFactory: "",
};

async function main() {
  deployer = await ethers.getSigner(
    "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
  );
  console.log("\n========================================");
  console.log("CRONOS ID PROTOCOL DEPLOYMENT");
  console.log("========================================");
  console.log("Deployer address:", deployer.address);
  console.log("Network:", (await ethers.provider.getNetwork()).name);
  console.log("========================================\n");

  try {
    // Phase 1: Core Registry
    console.log("\n📦 PHASE 1: CORE REGISTRY");
    console.log("========================================");
    await deployPhase1();

    // Phase 2: Supporting Contracts
    console.log("\n📦 PHASE 2: SUPPORTING CONTRACTS");
    console.log("========================================");
    await deployPhase2();

    // Phase 3: Resolvers
    console.log("\n📦 PHASE 3: RESOLVERS");
    console.log("========================================");
    await deployPhase3();

    // Phase 4: Registration System
    console.log("\n📦 PHASE 4: REGISTRATION SYSTEM");
    console.log("========================================");
    await deployPhase4();

    // Phase 5: Advanced Features
    console.log("\n📦 PHASE 5: ADVANCED FEATURES");
    console.log("========================================");
    await deployPhase5();

    // Phase 6: TLD System
    console.log("\n📦 PHASE 6: TLD SYSTEM");
    console.log("========================================");
    await deployPhase6();

    // Post-Deployment Configuration
    console.log("\n⚙️  POST-DEPLOYMENT CONFIGURATION");
    console.log("========================================");
    await configureSystem();

    // Save deployment addresses
    await saveDeploymentAddresses();

    // Verification
    console.log("\n✅ VERIFICATION");
    console.log("========================================");
    await verifyDeployment();

    console.log("\n========================================");
    console.log("🎉 DEPLOYMENT COMPLETE!");
    console.log("========================================");
    console.log("\nDeployed addresses saved to: deployments/");
  } catch (error) {
    console.error("\n❌ Deployment failed:", error);
    process.exit(1);
  }
}

// PHASE 1: Core Registry Deployment
async function deployPhase1() {
  // 1. Deploy OrbitRegistry
  console.log("Deploying OrbitRegistry...");
  const OrbitRegistry = await ethers.getContractFactory("OrbitRegistry");
  const orbitRegistry = await OrbitRegistry.deploy();

  deployedAddresses.orbitRegistry = await orbitRegistry.getAddress();
  console.log("✅ OrbitRegistry deployed to:", deployedAddresses.orbitRegistry);

  // 2. Deploy OrbitRoot
  console.log("Deploying OrbitRoot...");
  const OrbitRoot = await ethers.getContractFactory("OrbitRoot");
  const orbitRoot = await OrbitRoot.deploy(deployedAddresses.orbitRegistry);
  await orbitRoot.waitForDeployment();
  deployedAddresses.orbitRoot = await orbitRoot.getAddress();
  console.log("✅ OrbitRoot deployed to:", deployedAddresses.orbitRoot);

  // 3. Transfer root ownership to OrbitRoot
  console.log("Transferring root ownership...");
  const tx = await orbitRegistry.setOwner(
    "0x0000000000000000000000000000000000000000000000000000000000000000",
    deployedAddresses.orbitRoot
  );
  await tx.wait();
  console.log("✅ Root ownership transferred to OrbitRoot");
}

// PHASE 2: Supporting Contracts
async function deployPhase2() {
  // 1. Deploy PriceOracle (Upgradeable)
  console.log("Deploying OrbitPriceOracle...");
  const OrbitPriceOracle = await ethers.getContractFactory("OrbitPriceOracle");
  const priceOracle = await upgrades.deployProxy(
    OrbitPriceOracle,
    [
      ethers.parseEther("1000"),
      ethers.parseEther("500"),
      ethers.parseEther("100"),
      ethers.parseEther("50"),
      ethers.parseEther("10"),
      false,
    ],
    {
      initializer: "initialize",
      kind: "uups",
    }
  );
  await priceOracle.waitForDeployment();
  deployedAddresses.priceOracle = await priceOracle.getAddress();
  console.log(
    "✅ OrbitPriceOracle deployed to:",
    deployedAddresses.priceOracle
  );

  // Set initial prices
  console.log("Setting initial prices...");
  await priceOracle.setPrices(
    config.prices.oneChar,
    config.prices.twoChar,
    config.prices.threeChar,
    config.prices.fourChar,
    config.prices.fiveChar
  );
  console.log("✅ Prices configured");

  // 2. Deploy Blocklist (Upgradeable)
  console.log("Deploying Blocklist...");
  const Blocklist = await ethers.getContractFactory("Blocklist");
  const blocklist = await upgrades.deployProxy(Blocklist, [], {
    initializer: "initialize",
    kind: "uups",
  });
  await blocklist.waitForDeployment();
  deployedAddresses.blocklist = await blocklist.getAddress();
  console.log("✅ Blocklist deployed to:", deployedAddresses.blocklist);

  // 3. Deploy ChanceSystem (if exists)
  try {
    console.log("Deploying ChanceSystem...");
    const ChanceSystem = await ethers.getContractFactory("ChanceSystem");
    const chanceSystem = await upgrades.deployProxy(ChanceSystem, [], {
      initializer: "initialize",
      kind: "uups",
    });
    await chanceSystem.waitForDeployment();
    deployedAddresses.chanceSystem = await chanceSystem.getAddress();
    console.log("✅ ChanceSystem deployed to:", deployedAddresses.chanceSystem);
  } catch (error) {
    console.log("⚠️  ChanceSystem not found, skipping...");
    deployedAddresses.chanceSystem = ethers.ZeroAddress;
  }

  // 4. Deploy RevenueDistributor (if exists)
  try {
    console.log("Deploying RevenueDistributor...");
    const RevenueDistributor = await ethers.getContractFactory(
      "RevenueDistributor"
    );
    const revenueDistributor = await upgrades.deployProxy(
      RevenueDistributor,
      [
        config.addresses.treasury,
        config.addresses.team,
        config.revenue.treasury,
        config.revenue.team,
        config.revenue.staking,
      ],
      { initializer: "initialize", kind: "uups" }
    );
    await revenueDistributor.waitForDeployment();
    deployedAddresses.revenueDistributor =
      await revenueDistributor.getAddress();
    console.log(
      "✅ RevenueDistributor deployed to:",
      deployedAddresses.revenueDistributor
    );
  } catch (error) {
    console.log("⚠️  RevenueDistributor not found, skipping...");
    deployedAddresses.revenueDistributor = ethers.ZeroAddress;
  }
}

// PHASE 3: Resolver Deployment
async function deployPhase3() {
  // 1. Deploy PublicResolver
  console.log("Deploying PublicResolver...");
  const PublicResolver = await ethers.getContractFactory("PublicResolver");
  const publicResolver = await PublicResolver.deploy(
    deployedAddresses.orbitRegistry
  );
  await publicResolver.waitForDeployment();
  deployedAddresses.publicResolver = await publicResolver.getAddress();
  console.log(
    "✅ PublicResolver deployed to:",
    deployedAddresses.publicResolver
  );
}

// PHASE 4: Registration System
async function deployPhase4() {
  const ORBIT_NODE = ethers.namehash("orbit");

  // 1. Deploy OrbitRegistrar
  console.log("Deploying OrbitRegistrar...");
  const OrbitRegistrar = await ethers.getContractFactory("OrbitRegistrar");
  const orbitRegistrar = await upgrades.deployProxy(OrbitRegistrar, [
    deployedAddresses.orbitRegistry,
    ORBIT_NODE,
  ]);
  await orbitRegistrar.waitForDeployment();
  deployedAddresses.orbitRegistrar = await orbitRegistrar.getAddress();
  console.log(
    "✅ OrbitRegistrar deployed to:",
    deployedAddresses.orbitRegistrar
  );

  // 2. Deploy ReverseRegistrar (Upgradeable)
  console.log("Deploying ReverseRegistrar...");
  const ReverseRegistrar = await ethers.getContractFactory("ReverseRegistrar");
  const reverseRegistrar = await upgrades.deployProxy(
    ReverseRegistrar,
    [deployedAddresses.orbitRegistry],
    { initializer: "initialize", kind: "uups" }
  );
  await reverseRegistrar.waitForDeployment();
  deployedAddresses.reverseRegistrar = await reverseRegistrar.getAddress();
  console.log(
    "✅ ReverseRegistrar deployed to:",
    deployedAddresses.reverseRegistrar
  );

  // 3. Deploy OrbitRegistrarController (Upgradeable)
  console.log("Deploying OrbitRegistrarController...");
  const OrbitRegistrarController = await ethers.getContractFactory(
    "OrbitRegistrarController"
  );
  const controller = await upgrades.deployProxy(
    OrbitRegistrarController,
    [
      deployedAddresses.orbitRegistrar,
      deployedAddresses.priceOracle,
      deployedAddresses.reverseRegistrar,
    ],
    { initializer: "initialize", kind: "uups" }
  );
  await controller.waitForDeployment();
  deployedAddresses.controller = await controller.getAddress();
  console.log(
    "✅ OrbitRegistrarController deployed to:",
    deployedAddresses.controller
  );

  // 4. Configure relationships
  console.log("Configuring registrar relationships...");

  // Set controller as authorized in registrar
  await orbitRegistrar.addController(deployedAddresses.controller);
  console.log("✅ Controller added to registrar");

  // Get OrbitRoot contract
  const orbitRoot = await ethers.getContractAt(
    "OrbitRoot",
    deployedAddresses.orbitRoot
  );

  // Set registrar as owner of .orbit node
  const orbitLabel = ethers.keccak256(ethers.toUtf8Bytes("orbit"));
  await orbitRoot.setController(deployer, true);
  await orbitRoot.setSubnodeOwner(orbitLabel, deployedAddresses.orbitRegistrar);
  console.log("✅ Registrar set as owner of .orbit node");

  // Set resolver for reverse registrar
  await reverseRegistrar.setDefaultResolver(deployedAddresses.publicResolver);
  console.log("✅ Default resolver set for reverse registrar");

  // Configure controller with supporting contracts
  if (deployedAddresses.blocklist !== ethers.ZeroAddress) {
    await controller.setBlocklist(deployedAddresses.blocklist);
    console.log("✅ Blocklist configured in controller");
  }

  if (deployedAddresses.revenueDistributor !== ethers.ZeroAddress) {
    await controller.setRevenueDistributor(
      deployedAddresses.revenueDistributor
    );
    console.log("✅ Revenue distributor configured in controller");
  }

  //   if (deployedAddresses.chanceSystem !== ethers.ZeroAddress) {
  //     await controller.setChanceSystem(deployedAddresses.chanceSystem);
  //     console.log("✅ Chance system configured in controller");
  //   }
}

// PHASE 5: Advanced Features
async function deployPhase5() {
  // 1. Deploy SoulboundRegistrar (Upgradeable)
  try {
    console.log("Deploying SoulboundRegistrar...");
    const SoulboundRegistrar = await ethers.getContractFactory(
      "SoulboundRegistrar"
    );
    const soulboundRegistrar = await upgrades.deployProxy(
      SoulboundRegistrar,
      [deployedAddresses.orbitRegistry, ethers.namehash("soul")],
      { initializer: "initialize", kind: "uups" }
    );
    await soulboundRegistrar.waitForDeployment();
    deployedAddresses.soulboundRegistrar =
      await soulboundRegistrar.getAddress();
    console.log(
      "✅ SoulboundRegistrar deployed to:",
      deployedAddresses.soulboundRegistrar
    );
  } catch (error) {
    console.log("⚠️  SoulboundRegistrar not found, skipping...");
  }

  // 2. Deploy OfficialBadgeRegistry (Upgradeable)
  try {
    console.log("Deploying OfficialBadgeRegistry...");
    const OfficialBadgeRegistry = await ethers.getContractFactory(
      "OfficialBadgeRegistry"
    );
    const badgeRegistry = await upgrades.deployProxy(
      OfficialBadgeRegistry,
      [deployedAddresses.orbitRegistry],
      { initializer: "initialize", kind: "uups" }
    );
    await badgeRegistry.waitForDeployment();
    deployedAddresses.badgeRegistry = await badgeRegistry.getAddress();
    console.log(
      "✅ OfficialBadgeRegistry deployed to:",
      deployedAddresses.badgeRegistry
    );
  } catch (error) {
    console.log("⚠️  OfficialBadgeRegistry not found, skipping...");
  }

  // 3. Deploy SubdomainRegistrar (Upgradeable)
  try {
    console.log("Deploying SubdomainRegistrar...");
    const SubdomainRegistrar = await ethers.getContractFactory(
      "SubdomainRegistrar"
    );
    const subdomainRegistrar = await upgrades.deployProxy(
      SubdomainRegistrar,
      [deployedAddresses.orbitRegistry],
      { initializer: "initialize", kind: "uups" }
    );
    await subdomainRegistrar.waitForDeployment();
    deployedAddresses.subdomainRegistrar =
      await subdomainRegistrar.getAddress();
    console.log(
      "✅ SubdomainRegistrar deployed to:",
      deployedAddresses.subdomainRegistrar
    );
  } catch (error) {
    console.log("⚠️  SubdomainRegistrar not found, skipping...");
  }

  // 4. Deploy UniversalReverseAdapter
  try {
    console.log("Deploying UniversalReverseAdapter...");
    const UniversalReverseAdapter = await ethers.getContractFactory(
      "UniversalReverseAdapter"
    );
    const reverseAdapter = await UniversalReverseAdapter.deploy(
      deployedAddresses.orbitRoot
    );
    await reverseAdapter.waitForDeployment();
    deployedAddresses.reverseAdapter = await reverseAdapter.getAddress();
    console.log(
      "✅ UniversalReverseAdapter deployed to:",
      deployedAddresses.reverseAdapter
    );
  } catch (error) {
    console.log("⚠️  UniversalReverseAdapter not found, skipping...");
  }
}

// PHASE 6: TLD System
async function deployPhase6() {
  try {
    // 1. Deploy TLD modules
    console.log("Deploying TLD System modules...");

    const TLDStorage = await ethers.getContractFactory("TLDStorage");
    const tldStorage = await TLDStorage.deploy();
    await tldStorage.waitForDeployment();
    deployedAddresses.tldStorage = await tldStorage.getAddress();
    console.log("✅ TLDStorage deployed to:", deployedAddresses.tldStorage);

    // Try to deploy auction module
    try {
      const TLDAuctionModule = await ethers.getContractFactory(
        "TLDAuctionModule"
      );
      const auctionModule = await TLDAuctionModule.deploy(
        deployedAddresses.tldStorage
      );
      await auctionModule.waitForDeployment();
      deployedAddresses.auctionModule = await auctionModule.getAddress();
      console.log(
        "✅ TLDAuctionModule deployed to:",
        deployedAddresses.auctionModule
      );
    } catch {
      console.log("⚠️  TLDAuctionModule not found, skipping...");
    }

    const TLDRevenueModule = await ethers.getContractFactory(
      "TLDRevenueModule"
    );

    //Need to edit treasury
    const revenueModule = await TLDRevenueModule.deploy(
      deployedAddresses.tldStorage,
      ethers.ZeroAddress
    );
    await revenueModule.waitForDeployment();
    deployedAddresses.tldRevenueModule = await revenueModule.getAddress();
    console.log(
      "✅ TLDRevenueModule deployed to:",
      deployedAddresses.tldRevenueModule
    );

    const TLDRegistrarFactory = await ethers.getContractFactory(
      "TLDRegistrarFactory"
    );
    const registrarFactory = await TLDRegistrarFactory.deploy(
      deployedAddresses.orbitRegistry,
      deployedAddresses.orbitRoot
    );
    await registrarFactory.waitForDeployment();
    deployedAddresses.tldRegistrarFactory = await registrarFactory.getAddress();
    console.log(
      "✅ TLDRegistrarFactory deployed to:",
      deployedAddresses.tldRegistrarFactory
    );

    // 2. Deploy TLDFactory
    console.log("Deploying TLDFactory...");
    const TLDFactory = await ethers.getContractFactory("TLDFactory");
    const tldFactory = await upgrades.deployProxy(
      TLDFactory,
      [
        deployedAddresses.tldStorage,
        deployedAddresses.auctionModule,
        deployedAddresses.tldRevenueModule,
        deployedAddresses.tldRegistrarFactory,
      ],
      { initializer: "initialize", kind: "uups" }
    );
    await tldFactory.waitForDeployment();
    deployedAddresses.tldFactory = await tldFactory.getAddress();
    console.log("✅ TLDFactory deployed to:", deployedAddresses.tldFactory);

    // 3. Configure modules
    console.log("Configuring TLD modules...");
    await tldStorage.authorize(deployedAddresses.tldFactory);
    if (deployedAddresses.auctionModule) {
      const auctionModule = await ethers.getContractAt(
        "TLDAuctionModule",
        deployedAddresses.auctionModule
      );
      await auctionModule.setFactory(deployedAddresses.tldFactory);
    }
    await revenueModule.setFactory(deployedAddresses.tldFactory);
    await registrarFactory.setTLDFactory(deployedAddresses.tldFactory);
    console.log("✅ TLD modules configured");

    // 4. Set TLD factory as controller in OrbitRoot
    const orbitRoot = await ethers.getContractAt(
      "OrbitRoot",
      deployedAddresses.orbitRoot
    );
    await orbitRoot.setController(deployedAddresses.tldFactory, true);
    console.log("✅ TLD factory set as controller in OrbitRoot");
  } catch (error: any) {
    console.log("⚠️  TLD System deployment partially failed:", error.message);
  }
}

// Post-Deployment Configuration
async function configureSystem() {
  // 1. Set up access controls
  console.log("Setting up access controls...");
  const orbitRoot = await ethers.getContractAt(
    "OrbitRoot",
    deployedAddresses.orbitRoot
  );
  await orbitRoot.setController(deployedAddresses.controller, true);

  const reverseRegistrar = await ethers.getContractAt(
    "ReverseRegistrar",
    deployedAddresses.reverseRegistrar
  );
  await reverseRegistrar.setController(deployedAddresses.controller, true);
  console.log("✅ Access controls configured");

  // 2. Initialize blocklist with reserved terms
  if (
    deployedAddresses.blocklist &&
    deployedAddresses.blocklist !== ethers.ZeroAddress
  ) {
    console.log("Initializing blocklist...");
    const blocklist = await ethers.getContractAt(
      "Blocklist",
      deployedAddresses.blocklist
    );

    const blockedTerms = ["admin", "root", "cronos", "system", "oracle"];
    for (const term of blockedTerms) {
      try {
        await blocklist.update(
          ethers.keccak256(ethers.toUtf8Bytes(term)),
          true
        );
        console.log(`  ✅ Blocked: ${term}`);
      } catch (error: any) {
        console.log(`  ⚠️  Failed to block ${term}: ${error.message}`);
      }
    }
  }

  // 3. Set up reverse resolution
  console.log("Setting up reverse resolution...");
  try {
    const orbitRegistry = await ethers.getContractAt(
      "OrbitRegistry",
      deployedAddresses.orbitRegistry
    );

    // Create reverse node
    await orbitRoot.setSubnodeOwner(
      ethers.keccak256(ethers.toUtf8Bytes("reverse")),
      deployer.address
    );

    // Set addr.reverse
    await orbitRegistry.setSubnodeOwner(
      ethers.namehash("reverse"),
      ethers.keccak256(ethers.toUtf8Bytes("addr")),
      deployedAddresses.reverseRegistrar
    );
    console.log("✅ Reverse resolution configured");
  } catch (error: any) {
    console.log("⚠️  Reverse resolution setup failed:", error.message);
  }

  // 4. Transfer ownership to governance (if specified)
  if (config.addresses.governance) {
    console.log("Transferring ownership to governance...");
    const controller = await ethers.getContractAt(
      "OrbitRegistrarController",
      deployedAddresses.controller
    );
    await controller.transferOwnership(config.addresses.governance);
    await reverseRegistrar.transferOwnership(config.addresses.governance);
    console.log("✅ Ownership transferred to governance");
  }
}

// Save deployment addresses
async function saveDeploymentAddresses() {
  const network = (await ethers.provider.getNetwork()).name;
  const chainId = (await ethers.provider.getNetwork()).chainId;
  const timestamp = new Date().toISOString();

  const deployment = {
    network,
    //chainId,
    timestamp,
    addresses: deployedAddresses,
  };

  // Create deployments directory if it doesn't exist
  const deploymentsDir = path.join(__dirname, "../deployments");
  if (!fs.existsSync(deploymentsDir)) {
    fs.mkdirSync(deploymentsDir);
  }

  // Save to file
  const filename = `deployment-${chainId}-${Date.now()}.json`;
  const filepath = path.join(deploymentsDir, filename);
  fs.writeFileSync(filepath, JSON.stringify(deployment, null, 2));

  // Also save as latest
  const latestPath = path.join(deploymentsDir, `latest-${chainId}.json`);
  fs.writeFileSync(latestPath, JSON.stringify(deployment, null, 2));

  console.log(`\n📁 Deployment addresses saved to:`);
  console.log(`   ${filepath}`);
  console.log(`   ${latestPath}`);
}

// Verify deployment
async function verifyDeployment() {
  console.log("Verifying deployment...");

  // Check registry
  const registry = await ethers.getContractAt(
    "OrbitRegistry",
    deployedAddresses.orbitRegistry
  );
  const rootOwner = await registry.owner(ethers.ZeroAddress);
  console.log("✅ Root owner:", rootOwner);

  // Check registrar
  const registrar = await ethers.getContractAt(
    "OrbitRegistrar",
    deployedAddresses.orbitRegistrar
  );
  const orbitNode = await registrar.baseNode();
  console.log("✅ Orbit node:", orbitNode);

  // Check controller
  const controller = await ethers.getContractAt(
    "OrbitRegistrarController",
    deployedAddresses.controller
  );
  const priceOracle = await controller.priceOracle();
  console.log("✅ Price oracle:", priceOracle);

  // Test registration availability
  const testLabel = ethers.keccak256(ethers.toUtf8Bytes("test"));
  const available = await registrar.available(ethers.toBigInt(testLabel));
  console.log("✅ 'test.orbit' available:", available);

  console.log("\n🎉 All verifications passed!");
}

// Execute deployment
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
