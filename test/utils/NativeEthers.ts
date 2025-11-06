import { ethers } from "ethers";

function getProvider(
  rpcUrl: string,
  ensAddress: string,
  chainId: bigint,
  name: string
): ethers.JsonRpcProvider {
  console.log(Number(chainId.toString()));
  return new ethers.JsonRpcProvider(rpcUrl, {
    ensAddress: ensAddress,
    chainId: Number(chainId.toString()),
    name: name,
    ensNetwork: Number(chainId.toString()),
  });
}

export { getProvider };
