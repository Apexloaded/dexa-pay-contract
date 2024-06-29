import { ethers, upgrades, network } from "hardhat";

async function main() {
  const [owner] = await ethers.getSigners();
  const DexaPay = await ethers.getContractFactory("DexaPay");
  console.log("Upgrading DexaPay...");
  const dexaPay = await upgrades.upgradeProxy(
    "0xB1bCC3f7AD8B760dbD3b7d6159E5640F8b3Fc786",
    DexaPay
  );
  await dexaPay.waitForDeployment();
  const dexaPayAddr = await dexaPay.getAddress();
  console.log("DexaPay upgraded to:", dexaPayAddr);

  // await dexaPay.batchEnlistTokens([
  //   "0xBf3edC332bd9E1C32D10d2511B61938D1A6b4D01",
  //   "0xE8a8f500301c778064E380E5bFA9E315a7638134",
  // ]);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
