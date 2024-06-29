import { ethers, upgrades, network } from "hardhat";

async function main() {
  const [owner] = await ethers.getSigners();
  const DexaPay = await ethers.getContractFactory("DexaPay");
  console.log("Deploying DexaPay...");
  const dexaPay = await upgrades.deployProxy(DexaPay, [owner.address], {
    initializer: "init_dexa_pay",
    initialOwner: owner.address,
  });
  await dexaPay.waitForDeployment();
  const dexaPayAddr = await dexaPay.getAddress();
  console.log("DexaPay deployed to:", dexaPayAddr);

  const DexaBill = await ethers.getContractFactory("DexaBill");
  console.log("Deploying DexaBill...");
  const dexaBill = await upgrades.deployProxy(
    DexaBill,
    [owner.address, dexaPayAddr, "https://www.dexapay.xyz"],
    {
      initializer: "init_dexa_bill",
      initialOwner: owner.address,
    }
  );
  await dexaBill.waitForDeployment();
  const dexaBillAddr = await dexaBill.getAddress();
  console.log("DexaBill deployed to:", dexaBillAddr);

  await dexaPay.init_roles(dexaBillAddr);
  await dexaBill.init_roles(dexaPayAddr);
  await dexaPay.batchEnlistTokens([
    "0xBf3edC332bd9E1C32D10d2511B61938D1A6b4D01",
    "0xE8a8f500301c778064E380E5bFA9E315a7638134",
  ]);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
