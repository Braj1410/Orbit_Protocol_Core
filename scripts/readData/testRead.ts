import { ethers } from "hardhat";
import {
  OrbitRegistry,
  OrbitRoot,
  Blocklist,
  TLDStorage,
  TLDAuctionModule,
  TLDRevenueModule,
  TLDRegistrarFactory,
  TLDFactory__factory,
  TLDStorage__factory,
  TLDFactory,
} from "../../typechain-types";
import { AbiCoder, keccak256 } from "ethers";

let contracts = {
  OrbitRegistry: "0x306CF0ca8F289e13985587a3303De0Fa765b5B6f",
  Blocklist: "0x6e7cfe3fd749F6E1C53BC1065fc702eb6c22F600",
  storage: "0x3857C14Ec0C727ac2aEcD5016283C76c6b5C860e",
  auction: "0xeC406dA90079339a828DE424C9BF5ab58F851eE9",
  revenue: "0x93140112610128D738b264E1a913CC2142548BfB",
  registrarFactory: "0x4C3bE443B62c1C2B0b87A5D47cE4837B81772790",
  factory: "0xFb32dd376fF1c6E55CF522610C52d38A584a1986",
  orbitRoot: "0x968b1F578F9c225fa7e56A725B4aEB74813882a2",
};

async function main() {
  const factory = await ethers.getContractAt("TLDFactory", contracts.factory);
  const tldData = await factory.getTLD(1);

  console.log(ethers.decodeBytes32String(tldData.name));
}

main();
