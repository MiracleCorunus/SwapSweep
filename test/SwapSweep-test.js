/* eslint-disable */

const poolJson = require('@uniswap/v3-core/artifacts/contracts/UniswapV3Pool.sol/UniswapV3Pool.json')
const routerJson = require('@uniswap/v3-periphery/artifacts/contracts/SwapRouter.sol/SwapRouter.json')
const usdcJson = require('../artifacts/contracts/Usdc.sol/Usdc.json');
const wethJson = require('../artifacts/contracts/WETH9.sol/WETH9.json');

const { expect } = require('chai')
const { network, ethers } = require('hardhat')

const SWAP_ROUTER_ADDR = '0xE592427A0AEce92De3Edee1F18E0157C05861564'
const USDC_ETH_POOL_ADDR = '0x8ad599c3A0ff1De082011EFDDc58f1908eb6e6D8'
const ADDRESS_CTOKEN0 = '0x39AA39c021dfbaE8faC545936693aC917d5E7563'
const ADDRESS_CTOKEN1 = '0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5'
const USDC_ADDRESS = '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48'
const WETH_ADDRESS = '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2'

const tickBounds = [207240, 185640]

describe('Testing Cases on SwapSweep Contract', function () {
    let deployer, account1, account2;
    const gweiGasPrice = 21;

    before(async function () {
        [deployer, account1, account2] = await ethers.getSigners();

        params = {
            from: deployer.address,
            gasLimit: (1300000).toFixed(0),
            gasPrice: gweiGasPrice * 1e9,
            type: '0x0',
        };

        this.silo0 = await (await ethers.getContractFactory('CompoundCTokenSilo', deployer)).deploy(ADDRESS_CTOKEN0);
        console.log(`CToken Silo deployed to ${this.silo0.address}`);

        this.silo1 = await (await ethers.getContractFactory('CompoundCEtherSilo', deployer)).deploy(ADDRESS_CTOKEN1);
        console.log(`CEth Silo deployed to ${this.silo1.address}`);

        this.uniswapRouter = new ethers.Contract(SWAP_ROUTER_ADDR, routerJson.abi, ethers.provider);
        this.uniswapPool = new ethers.Contract(USDC_ETH_POOL_ADDR, poolJson.abi, ethers.provider);
        this.usdc = new ethers.Contract(USDC_ADDRESS, usdcJson.abi, ethers.provider);
        this.weth = new ethers.Contract(WETH_ADDRESS, wethJson.abi, ethers.provider);

        const tick_spacing = await this.uniswapPool.tickSpacing();

        expect(tick_spacing.toString()).to.equal("60");

        this.swapSweep = await (
            await ethers.getContractFactory('SwapSweep', deployer)
        ).deploy(
            this.uniswapPool.address,
            this.uniswapRouter.address,
            this.silo0.address,
            this.silo1.address,
            tickBounds[1],
            tickBounds[0],
            15,
        );

        console.log(`SwapSweep Contract is Deployed to ${this.swapSweep.address}`);

        /** Send USDC to deployer & account1 & account2 */
        await network.provider.request({
            method: "hardhat_impersonateAccount",
            params: ["0x5c985e89dde482efe97ea9f1950ad149eb73829b"],
        });

        const signer = await ethers.getSigner("0x5c985e89dde482efe97ea9f1950ad149eb73829b")

        await this.usdc.connect(signer).approve(deployer.address, 1000000000000000);
        await this.usdc.connect(deployer).transferFrom(signer.address, deployer.address, 10000000000);

        expect(await this.usdc.balanceOf(deployer.address)).to.be.eq('10000000000')

        await this.usdc.connect(signer).approve(account1.address, 1000000000000000);
        await this.usdc.connect(account1).transferFrom(signer.address, account1.address, 10000000000);
        expect(await this.usdc.balanceOf(account1.address)).to.be.eq('10001000000')

        await this.usdc.connect(signer).approve(account2.address, 1000000000000000);
        await this.usdc.connect(account2).transferFrom(signer.address, account2.address, 10000000000);

        expect(await this.usdc.balanceOf(account2.address)).to.be.eq('10000000000')

        /** Get WETH with Test ETH with Deposit function */

        await this.weth.connect(deployer).deposit({ value: ethers.utils.parseEther("100") });
        expect(await this.weth.balanceOf(deployer.address)).to.be.eq(ethers.utils.parseEther("100"));

        await this.weth.connect(account1).deposit({ value: ethers.utils.parseEther("100") });
        expect(await this.weth.balanceOf(account1.address)).to.be.eq(ethers.utils.parseEther("100"));

        await this.weth.connect(account2).deposit({ value: ethers.utils.parseEther("100") });
        expect(await this.weth.balanceOf(account2.address)).to.be.eq(ethers.utils.parseEther("100"));

    });
    it('Test Case for Deposit Function', async function () {
        params = {
            from: deployer.address,
            gasLimit: (1300000).toFixed(0),
            gasPrice: gweiGasPrice * 1e9,
            type: '0x0',
        };

        const slot0 = await this.uniswapPool.slot0();
        console.log("Slot datas", slot0.sqrtPriceX96, slot0.tick);

        const silo0Balance0 = await this.silo0.balanceOf(this.swapSweep.address);
        const silo0Balance1 = await this.silo0.balanceOf(deployer.address);

        console.log("Silo0 balance", silo0Balance0.toString(), silo0Balance1.toString());

        await this.usdc.connect(deployer).approve(this.swapSweep.address, 10000000000);
        await this.weth.connect(deployer).approve(this.swapSweep.address, 100000000);

        await this.swapSweep.connect(deployer).deposit([10000000000, 100000000, 0, 0, 1]);
    });


});