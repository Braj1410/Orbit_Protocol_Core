import { ethers } from "hardhat";

async function Run() {
  const contracts = {
    OrbitRegistry: "0xD4B20e3247a951F52944c7F4022eea849B90A226",
    Blocklist: "0xF5D4b40ae0e76aC407A5fe35b18e7e8a514b6b14",
    storage: "0xc46BAe6D59bF660885d00708e3A3c975A0451D4d",
    auction: "0x02CE97A5619Aef1CDa384eA1aB7896C6ef76Ac9D",
    revenue: "0x19f92311cA3afCF521Cd35B9a309C31b178fcE56",
    registrarFactory: "0x73df7f51785653E77d6aB0d1bA311D6DF9999b71",
    factory: "0xD01CBf94204233AA2f841d6bB1606BD49F72B99D",
    orbitRoot: "0x92fFf0B2116e50d99baEA6A4Ee020b6877ABEEe5",
  };

  const orbitRoot = await ethers.getContractAt(
    "OrbitRoot",
    contracts.orbitRoot
  );

  const RootNode = await orbitRoot.ROOT_NODE();
  console.log(RootNode, "Rootnode");

  const TLDFactory = await ethers.getContractAt(
    "TLDFactory",
    contracts.factory
  );
  const tldData = await TLDFactory.getTLD(1);

  const registrar = await ethers.getContractAt(
    "TLDRegistrar",
    tldData.registrar
  );

  const registrarNode = await registrar.baseNode();
  console.log(registrarNode, "registrarNode");

  const orbitRegistry = await ethers.getContractAt(
    "OrbitRegistry",
    contracts.OrbitRegistry
  );

  const owner = await orbitRegistry.owner(registrarNode);

  console.log(owner, "owner");
}

Run();
