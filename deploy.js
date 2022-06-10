
const hre = require("hardhat");
const { artifacts } = require("hardhat");
const Factory = artifacts.require("Factory");
const CompoundCEtherSilo = artifacts.require("CompoundCEtherSilo");
const CompoundCTokenSilo = artifacts.require("CompoundCTokenSilo");
const SwapSweepResolver = artifacts.require("SwapSweepResolver");

const ADDRESS_UNI_POOL = "0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640";
const ADDRESS_CTOKEN0 = "0x39AA39c021dfbaE8faC545936693aC917d5E7563";
const ADDRESS_CTOKEN1 = "0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5";
const V3_SWAP_ROUTER_ADDRESS = '0xE592427A0AEce92De3Edee1F18E0157C05861564';
const tickBounds = [207240, 189330];
const gweiGasPrice = 21
async function main() {


  // We get the contract to deploy
  const deployer = web3.eth.accounts.privateKeyToAccount(process.env.DEPLOYER);
  const swapSweepFactory = await ethers.getContractFactory("SwapSweep");
  const bytecode = swapSweepFactory.bytecode
  const factory = await Factory.new(bytecode, {
    from: deployer.address,
    gasLimit: 7000000,
    gasPrice: gweiGasPrice * 1e9,
    type: "0x0",
  });

  console.log(`Factory deployed to ${factory.address}`);



  params = {
    from: deployer.address,
    gasLimit: (1300000).toFixed(0),
    gasPrice: gweiGasPrice * 1e9,
    type: "0x0",
  };

  const silo0 = await CompoundCTokenSilo.new(ADDRESS_CTOKEN0, params);
  console.log(`CToken Silo deployed to ${silo0.address}`);

  const silo1 = await CompoundCEtherSilo.new(ADDRESS_CTOKEN1, params);
  console.log(`CEther Silo deployed to ${silo1.address}`);

  const nonce = await web3.eth.getTransactionCount(deployer.address);

  const requiredGas = 1.05 * (await factory.createVault.estimateGas(
    ADDRESS_UNI_POOL,
    V3_SWAP_ROUTER_ADDRESS,
    silo0.address,
    silo1.address,
    tickBounds[1],
    tickBounds[0],
    3, {
    from: deployer.address,
    gasLimit: 6000000,
    gasPrice: 0,
    nonce: nonce,
    type: "0x0",
  }));

  const vault = await factory.createVault(
    ADDRESS_UNI_POOL,
    V3_SWAP_ROUTER_ADDRESS,
    silo0.address,
    silo1.address,
    tickBounds[1],
    tickBounds[0],
    3, {
    from: deployer.address,
    gasLimit: requiredGas.toFixed(0),
    gasPrice: gweiGasPrice * 1e9,
    nonce: nonce,
    type: "0x0",
  });

  const vaultAddress = vault.logs[0].args.vault;

  const resolver = await SwapSweepResolver.new(vaultAddress, params)
  console.log(`Resolver address ${resolver.address}`);

  console.info(`\nSuccessfully deployed vault!! Address: ${vaultAddress}`);
  console.info(`Please verify the contract on Etherscan with the following dapptools command:`);
  console.info(`\tdapp verify-contract contracts/SwapSweep.sol:SwapSweep ${vaultAddress} ${ADDRESS_UNI_POOL} ${silo0.address} ${silo1.address}\n`);

}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
