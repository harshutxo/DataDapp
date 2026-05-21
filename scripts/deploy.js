const hre = require("hardhat");

async function main() {
  const [deployer] = await hre.ethers.getSigners();
  const DataVault = await hre.ethers.getContractFactory("DataVault");
  const vault = await DataVault.deploy("Private Data Vault", "PDV");

  await vault.waitForDeployment();

  console.log("DataVault deployed by:", deployer.address);
  console.log("DataVault address:", await vault.getAddress());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
