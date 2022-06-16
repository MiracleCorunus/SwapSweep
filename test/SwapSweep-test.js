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

let shares;
let investorId;
let amount0;
let amount1;

describe('Testing Cases on SwapSweep Contract', function () {
    let deployer, david, carol;
    const gweiGasPrice = 21;

    before(async function () {
        [deployer, david, carol] = await ethers.getSigners();

        params = {
            from: deployer.address,
            gasLimit: (1300000).toFixed(0),
            gasPrice: gweiGasPrice * 1e9,
            type: '0x0',
        };

        this.silo0 = await (await ethers.getContractFactory('CompoundCTokenSilo', deployer)).deploy(ADDRESS_CTOKEN0);

        this.silo1 = await (await ethers.getContractFactory('CompoundCEtherSilo', deployer)).deploy(ADDRESS_CTOKEN1);

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
            3,
        );

        console.log(`SwapSweep Contract is Deployed to ${this.swapSweep.address}`);

        /** Send USDC to deployer & david & carol */
        await network.provider.request({
            method: "hardhat_impersonateAccount",
            params: ["0x5c985e89dde482efe97ea9f1950ad149eb73829b"],
        });

        const signer = await ethers.getSigner("0x5c985e89dde482efe97ea9f1950ad149eb73829b")
        await this.usdc.connect(signer).approve(deployer.address, 100000000000000);
        await this.usdc.connect(deployer).transferFrom(signer.address, deployer.address, 100000000000000);

        expect(await this.usdc.balanceOf(deployer.address)).to.be.eq('100000000000000')

        await this.usdc.connect(signer).approve(david.address, 10000000000000);
        await this.usdc.connect(david).transferFrom(signer.address, david.address, 10000000000);

        await this.usdc.connect(signer).approve(carol.address, 100000000000000);
        await this.usdc.connect(carol).transferFrom(signer.address, carol.address, 100000000000000);
        expect(await this.usdc.balanceOf(carol.address)).to.be.eq('100000000000000')

        /** Get WETH with Test ETH using Deposit function of WETH Contract*/

        await this.weth.connect(deployer).deposit({ value: ethers.utils.parseEther("100") });
        expect(await this.weth.balanceOf(deployer.address)).to.be.eq(ethers.utils.parseEther("100"));

        await this.weth.connect(david).deposit({ value: ethers.utils.parseEther("100") });
        expect(await this.weth.balanceOf(david.address)).to.be.eq(ethers.utils.parseEther("100"));

        await this.weth.connect(carol).deposit({ value: ethers.utils.parseEther("100") });
        expect(await this.weth.balanceOf(carol.address)).to.be.eq(ethers.utils.parseEther("100"));

        const ticks = await this.swapSweep.readTicks();
        console.log("Ticks Information: ", ticks);

    });
    it('Test Case for Deposit Function', async function () {
        params = {
            from: deployer.address,
            gasLimit: (1300000).toFixed(0),
            gasPrice: gweiGasPrice * 1e9,
            type: '0x0',
        };

        const slot0 = await this.uniswapPool.slot0();

        const silo0Balance0 = await this.silo0.balanceOf(this.swapSweep.address);
        const silo0Balance1 = await this.silo0.balanceOf(deployer.address);

        await this.usdc.connect(deployer).approve(this.swapSweep.address, 100000000000000);
        await this.weth.connect(deployer).approve(this.swapSweep.address, 10000000000);

        let tx = await this.swapSweep.connect(deployer).deposit([100000000000000, 10000000000, 0, 0, 1]);
        const { events } = await tx.wait();

        console.log("Events", events[events.length - 1].args);

        investorIds = events[events.length - 1].args.investorId;
        amount0 = events[events.length - 1].args.amount0;
        amount1 = events[events.length - 1].args.amount1;
        shares = events[events.length - 1].args.shares;

        console.log("Result of Deposit", investorIds, amount0, amount1, shares);

        console.log("balance of USDC => ", await this.usdc.balanceOf(deployer.address));
        console.log("balance of WETH => ", await this.weth.balanceOf(deployer.address));
        expect(await this.usdc.balanceOf(deployer.address)).to.be.eq(100000000000000 - amount0);
        // expect(await this.weth.balanceOf(deployer.address)).to.be.eq(ethers.utils.parseEther("100") - amount1);
    });

    it('Test Case for depositSilo function', async function () {
        await this.usdc.connect(david).approve(this.swapSweep.address, 500000000);
        await this.swapSweep.connect(david).depositSilo(this.silo0.address, 500000000);
    })

    it('Test Case for setMaxDeadline function', async function () {
        await this.swapSweep.connect(deployer).setMaxDeadline(80);
        expect(await this.swapSweep.maxDeadline()).to.be.eq(80);
    })

    it('Test Case for setMaxSlippageD function', async function () {
        await this.swapSweep.connect(deployer).setMaxSlippageD(6000000);
        expect(await this.swapSweep.maxSlippageD()).to.be.eq(6000000);
    })

    it('Test Case for rebalance function', async function () {
        let bcNumber = 0;
        await ethers.provider.getBlockNumber().then((blockNumber) => {
            console.log("Current block number: " + blockNumber);
            bcNumber = blockNumber
        });

        const timeStamp = (await ethers.provider.getBlock(bcNumber)).timestamp;
        console.log("Current TimeStamp", timeStamp);

        await this.swapSweep.rebalance(timeStamp + 50);
    })

    it('Test Case for reposition function must be reverted with tick in current uni bounds statement', async function () {
        const ticks = await this.swapSweep.readTicks();
        console.log("Ticks Information after rebalance: ", ticks);

        await expect(this.swapSweep.reposition()).to.be.reverted;
    })

    it('Test Case for Withdraw Function', async function () {
        let tx = await this.swapSweep.connect(deployer).withdraw(shares, 0, 0, 1);

        const { events } = await tx.wait();
        console.log("result of withdraw", events[events.length - 1].args);

        expect(events[events.length - 1].args.shares, shares);
    })
});