import { ethers, upgrades, network } from "hardhat";

async function main() {
  const [owner] = await ethers.getSigners();
  const DexaPay = await ethers.getContractFactory("DexaPay");
  console.log("Upgrading DexaPay...");
  const dexaPay = await upgrades.upgradeProxy(
    "0x890800109C5f42100111c42a89936a8DA1Cd1e9d",
    DexaPay
  );
  await dexaPay.waitForDeployment();
  const dexaPayAddr = await dexaPay.getAddress();
  console.log("DexaPay upgraded to:", dexaPayAddr);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
