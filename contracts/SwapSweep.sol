// SPDX-License-Identifier: AGPL-3.0-only
// solhint-disable no-empty-blocks
pragma solidity ^0.8.10;

import "hardhat/console.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./libraries/FullMath.sol";
import "./libraries/TickMath.sol";
import "./libraries/Silo.sol";
import "./libraries/Uniswap.sol";

import {IFactory} from "./interfaces/IFactory.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

import "./interfaces/ISwapSweepEvents.sol";
import "./interfaces/ISilo.sol";

import "./SwapSweepERC20.sol";
import "./UniswapHelper.sol";

// Add the functions that the resolver will call
// Make the resolver contract for the rebalance and reposition functions
// Modify the compound silo vault test to accomodate Swap Sweep.

uint256 constant Q96 = 2**96;

contract SwapSweep is SwapSweepERC20, UniswapHelper, ISwapSweepEvents, Ownable {
    using SafeERC20 for IERC20;
    using Uniswap for Uniswap.Position;
    // using Silo for ISilo;

    /// @dev The minimum tick that can serve as a position boundary in the Uniswap pool
    int24 private immutable MIN_TICK;

    /// @dev The maximum tick that can serve as a position boundary in the Uniswap pool
    int24 private immutable MAX_TICK;

    /// @dev The maximum slippage tolerance for swaps
    uint256 public maxSlippageD = 5 * 10**6;

    /// @dev The maximum time in seconds after the last block.timestamp that a swap can be executed.
    uint256 public maxDeadline = 60;

    /// @dev Uni v3 swap router
    ISwapRouter public router;

    /// @dev The tick sub range length; tickSubRangeLength = upperSubRange - lowerSubRange
    int24 public tickSubRangeLength;

    /// @dev Ratio of inventory in Uni position times DENOMINATOR
    uint256 public targetUniRatioD;

    uint256 public constant DENOMINATOR = 10**9;

    /// @dev silo that stores excess token0 in money market vault to earn interest
    ISilo public immutable silo0;

    /// @dev silo that stores excess token1 in money market vault to earn interest
    ISilo public immutable silo1;

    struct PackedSlot {
        // The primary position's lower tick bound
        int24 primaryLower;
        // The primary position's upper tick bound
        int24 primaryUpper;
    }

    PackedSlot public packedSlot;

    /// @dev Required for some silos
    receive() external payable {}

    constructor(
        IUniswapV3Pool _uniPool,
        ISwapRouter _router,
        ISilo _silo0,
        ISilo _silo1,
        int24 _minTick,
        int24 _maxTick,
        int24 _subDivisions // Number of equal tick length sub ranges that divides the _minTick _maxTick range.
    )
        SwapSweepERC20(
            // ex: Swap Sweep USDC/WETH
            string(
                abi.encodePacked(
                    "SwapSweep",
                    IERC20Metadata(_uniPool.token0()).symbol(),
                    "/",
                    IERC20Metadata(_uniPool.token1()).symbol()
                )
            )
        )
        UniswapHelper(_uniPool)
    {
        int24 _tickRange = _maxTick - _minTick;
        require(
            _tickRange % (TICK_SPACING * _subDivisions) == 0,
            "_tickRange % _subDivisions !=0"
        );
        _transferOwnership(tx.origin);
        tickSubRangeLength = _tickRange / (_subDivisions);
        targetUniRatioD = _targetTokenRatioD(
            _maxTick - tickSubRangeLength,
            _minTick,
            _maxTick
        );
        MIN_TICK = _minTick;
        MAX_TICK = _maxTick;

        silo0 = _silo0;
        silo1 = _silo1;
        router = _router;

        (, int24 tick, , , , , ) = UNI_POOL.slot0();
        int24 bound;

        if (tick < MAX_TICK) {
            bound = MAX_TICK;
            for (int24 i = 0; i < _subDivisions; ++i) {
                bound -= tickSubRangeLength;
                if (bound < tick) {
                    break;
                }
            }
            packedSlot.primaryLower = bound;
            packedSlot.primaryUpper = bound + tickSubRangeLength;
        } else {
            packedSlot.primaryLower = MAX_TICK - tickSubRangeLength;
            packedSlot.primaryUpper = MAX_TICK;
        }
    }

    function setMaxDeadline(uint256 _deadline) external onlyOwner {
        maxDeadline = _deadline;
    }

    function setMaxSlippageD(uint256 _maxSlippageD) external onlyOwner {
        maxSlippageD = _maxSlippageD;
    }

    struct DepositParams {
        uint256 amount0Max;
        uint256 amount1Max;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 investorId;
    }

    function deposit(DepositParams memory params)
        external
        onlyOwner
        returns (
            uint256 shares,
            uint256 amount0,
            uint256 amount1
        )
    {
        require(
            params.amount0Max != 0 || params.amount1Max != 0,
            "SwapSweep: 0 deposit"
        );
        Uniswap.Position memory primary = _loadPackedSlot();

        // Poke all assets
        primary.poke();
        Silo.delegate_poke(silo0);
        Silo.delegate_poke(silo1);

        (uint160 sqrtPriceX96, int24 tick, , , , , ) = UNI_POOL.slot0();
        (uint256 inventory0, uint256 inventory1) = _getInventory(
            primary,
            sqrtPriceX96
        );

        (shares, amount0, amount1) = _computeLPShares(
            totalSupply,
            inventory0,
            inventory1,
            params.amount0Max,
            params.amount1Max,
            sqrtPriceX96,
            tick
        );
        require(shares != 0, "SwapSweep: 0 shares");
        require(amount0 >= params.amount0Min, "SwapSweep: amount0 too low");
        require(amount1 >= params.amount1Min, "SwapSweep: amount1 too low");

        // Pull in tokens from sender
        TOKEN0.safeTransferFrom(msg.sender, address(this), amount0);
        TOKEN1.safeTransferFrom(msg.sender, address(this), amount1);

        // Calculate amount0Uni and amount1Uni
        (uint256 amount0Uni, uint256 amount1Uni) = _computeUniAmounts(
            amount0,
            amount1,
            tick,
            primary.lower,
            primary.upper
        );

        // Place some liquidity in Uniswap
        (amount0Uni, amount1Uni) = primary.deposit(
            primary.liquidityForAmounts(sqrtPriceX96, amount0Uni, amount1Uni)
        );

        // Place excess into silos
        uint256 balance0 = amount0 - amount0Uni;
        uint256 balance1 = amount1 - amount1Uni;
        if (balance0 != 0) {
            Silo.delegate_deposit(silo0, balance0);
        }
        if (balance1 != 0) {
            Silo.delegate_deposit(silo1, balance1);
        }
        // Mint shares
        _mint(msg.sender, params.investorId, shares);
        emit Deposit(msg.sender, params.investorId, shares, amount0, amount1);
    }

    function withdraw(
        uint256 shares,
        uint256 amount0Min,
        uint256 amount1Min,
        uint256 investorId
    ) external onlyOwner returns (uint256 amount0, uint256 amount1) {
        require(shares != 0, "SwapSweep: 0 shares");

        Uniswap.Position memory primary = _loadPackedSlot();

        // Poke silos to ensure reported balances are correct
        Silo.delegate_poke(silo0);
        Silo.delegate_poke(silo1);

        uint256 _totalSupply = totalSupply;
        uint256 a;
        uint256 b;
        uint256 c;
        uint256 d;

        // Compute user's portion of token0 from silo0
        b = silo0.balanceOf(address(this));
        amount0 = FullMath.mulDiv(b, shares, _totalSupply);
        // Withdraw from silo0
        Silo.delegate_withdraw(silo0, amount0);

        // Compute user's portion of token1 from silo1
        b = silo1.balanceOf(address(this));
        amount1 = FullMath.mulDiv(b, shares, _totalSupply);
        // Withdraw from silo1
        Silo.delegate_withdraw(silo1, amount1);

        // Withdraw user's portion of the primary position
        {
            (uint128 liquidity, , , , ) = primary.info();
            (a, b, c, d) = primary.withdraw(
                uint128(FullMath.mulDiv(liquidity, shares, _totalSupply))
            );
            amount0 += a + FullMath.mulDiv(c, shares, _totalSupply);
            amount1 += b + FullMath.mulDiv(d, shares, _totalSupply);
        }

        // Check constraints
        require(amount0 >= amount0Min, "SwapSweep: amount0 too low");
        require(amount1 >= amount1Min, "SwapSweep: amount1 too low");

        // Transfer tokens
        TOKEN0.safeTransfer(msg.sender, amount0);
        TOKEN1.safeTransfer(msg.sender, amount1);

        // Burn shares
        _burn(msg.sender, investorId, shares);
        emit Withdraw(msg.sender, investorId, shares, amount0, amount1);
    }

    struct RebalanceCache {
        uint160 sqrtPriceX96;
        uint224 priceX96;
        int24 tick;
    }

    function depositSilo(ISilo silo, uint256 amount) external {
        // Pull in tokens from sender
        TOKEN0.safeTransferFrom(msg.sender, address(this), amount);
        Silo.delegate_deposit(silo, amount);
    }

    function readTicks()
        external
        view
        returns (
            int24,
            int24,
            int24
        )
    {
        Uniswap.Position memory primary = _loadPackedSlot();
        (, int24 tick, , , , , ) = UNI_POOL.slot0();
        return (primary.lower, tick, primary.upper);
    }

    function rebalance(uint256 _deadline) external {
        require(
            block.timestamp + maxDeadline > _deadline,
            "block.timestamp + maxDeadline =< _deadline"
        );
        Uniswap.Position memory primary = _loadPackedSlot();

        // Populate rebalance cache
        RebalanceCache memory cache;
        (cache.sqrtPriceX96, cache.tick, , , , , ) = UNI_POOL.slot0();
        cache.priceX96 = uint224(
            FullMath.mulDiv(cache.sqrtPriceX96, cache.sqrtPriceX96, Q96)
        );
        // Poke silos to ensure reported balances are correct
        Silo.delegate_poke(silo0);
        Silo.delegate_poke(silo1);

        // Check inventory
        (uint256 inventory0, uint256 inventory1) = _getInventory(
            primary,
            cache.sqrtPriceX96
        );

        // Compute inventory ratio to determine what happens next
        uint256 ratio = FullMath.mulDiv(
            10_000,
            inventory0,
            inventory0 + FullMath.mulDiv(inventory1, Q96, cache.priceX96)
        );
        // Compute target ratio to determine what happens next
        uint256 _targetRatioD = _targetTokenRatioD(
            cache.tick,
            MIN_TICK,
            MAX_TICK
        );

        // calculate inventory1 in terms of token 0
        uint256 inventory1InToken0 = FullMath.mulDiv(
            inventory1,
            Q96,
            cache.priceX96
        );
        // calculate target inventory amount in token 0. This value will be used to determine how much of which token needs to be swapped.
        uint256 targetInventoryInToken0 = FullMath.mulDiv(
            inventory1InToken0 + inventory0,
            _targetRatioD,
            DENOMINATOR
        );
        uint256 _amountIn;
        uint256 _amountOutMinimum;
        SwapToTargetParams memory params;
        // if inventory ratio deviated by 2 percent of the target ratio rebalance.
        if (ratio < FullMath.mulDiv(_targetRatioD, 9800, DENOMINATOR)) {
            _amountIn = FullMath.mulDiv(
                targetInventoryInToken0 - inventory0,
                cache.priceX96,
                Q96
            );
            _amountOutMinimum = FullMath.mulDiv(_amountIn, Q96, cache.priceX96);
            params = SwapToTargetParams(
                _amountIn,
                _amountOutMinimum,
                TOKEN1,
                TOKEN0,
                silo1,
                silo0,
                _deadline,
                maxSlippageD
            );
            _swapToTarget(params);
        } else if (ratio > FullMath.mulDiv(_targetRatioD, 10200, DENOMINATOR)) {
            _amountIn = inventory0 - targetInventoryInToken0;
            _amountOutMinimum = FullMath.mulDiv(_amountIn, cache.priceX96, Q96);
            params = SwapToTargetParams(
                _amountIn,
                _amountOutMinimum,
                TOKEN0,
                TOKEN1,
                silo0,
                silo1,
                _deadline,
                maxSlippageD
            );
            _swapToTarget(params);
        }
        emit Rebalance(ratio, totalSupply, inventory0, inventory1);
    }

    struct SwapToTargetParams {
        uint256 _amountIn;
        uint256 _amountOutMinimum;
        IERC20 _tokenIn;
        IERC20 _tokenOut;
        ISilo _siloWithdraw;
        ISilo _siloDeposit;
        uint256 _deadline;
        uint256 _maxSlippageD;
    }

    function _swapToTarget(SwapToTargetParams memory params) internal {
        Silo.delegate_withdraw(params._siloWithdraw, params._amountIn);
        ISwapRouter.ExactInputSingleParams memory swapParams = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: address(params._tokenIn),
                tokenOut: address(params._tokenOut),
                fee: UNI_POOL.fee(),
                recipient: address(this),
                deadline: block.timestamp + 30,
                amountIn: params._amountIn,
                amountOutMinimum: FullMath.mulDiv(
                    params._amountOutMinimum,
                    DENOMINATOR - params._maxSlippageD,
                    DENOMINATOR
                ),
                sqrtPriceLimitX96: 0
            });
        params._tokenIn.safeApprove(address(router), params._amountIn);
        uint256 _amountOut = router.exactInputSingle(swapParams);
        params._tokenIn.safeApprove(address(router), 0);
        Silo.delegate_deposit(silo1, _amountOut);
    }

    struct PositionCache {
        uint256 uniExit0;
        uint256 uniExit1;
        uint256 earned0;
        uint256 earned1;
    }

    /**
     * @notice Moves the primary Uniswap position to adjacent sub range such that it is captuing the current tick. Deposits leftover funds into the silos.
     */
    function reposition() external {
        // Get uni position
        Uniswap.Position memory _primary = _loadPackedSlot();

        // Populate rebalance cache
        RebalanceCache memory cache;
        (cache.sqrtPriceX96, cache.tick, , , , , ) = UNI_POOL.slot0();
        cache.priceX96 = uint224(
            FullMath.mulDiv(cache.sqrtPriceX96, cache.sqrtPriceX96, Q96)
        );

        // Check to make sure that tick is out of current sub range and in larger range.
        require(
            cache.tick > _primary.upper || cache.tick < _primary.lower,
            "tick in current uni bounds"
        );
        require(
            cache.tick < MAX_TICK || cache.tick > MIN_TICK,
            "tick out of MIN MAX tick bounds"
        );

        // Poke silos to ensure reported balances are correct
        Silo.delegate_poke(silo0);
        Silo.delegate_poke(silo1);

        // Check inventory
        (uint256 _inventory0, uint256 _inventory1) = _getInventory(
            _primary,
            cache.sqrtPriceX96
        );
        // Exit primary Uniswap position
        PositionCache memory pCache;
        (uint128 liquidity, , , , ) = _primary.info();
        (
            pCache.uniExit0,
            pCache.uniExit1,
            pCache.earned0,
            pCache.earned1
        ) = _primary.withdraw(liquidity);

        // Update primary position's ticks
        if (cache.tick > _primary.upper) {
            unchecked {
                _primary.lower = _primary.upper;
                _primary.upper = _primary.upper + tickSubRangeLength;
            }
        } else {
            unchecked {
                _primary.upper = _primary.lower;
                _primary.lower = _primary.lower - tickSubRangeLength;
            }
        }

        // ...and compute amounts that should be placed inside uni position
        (uint256 _amount0, uint256 _amount1) = _computeUniAmounts(
            _inventory0,
            _inventory1,
            cache.tick,
            _primary.lower,
            _primary.upper
        );

        // If contract balance (exited uni positions) is insufficient, withdraw from silos
        uint256 balance0 = pCache.uniExit0 + pCache.earned0;
        uint256 balance1 = pCache.uniExit1 + pCache.earned1;
        unchecked {
            if (balance0 < _amount0) {
                _inventory0 = 0; // reuse var to avoid stack too deep. now a flag, 0 means we withdraw from silo0
                _amount0 = balance0 + _silo0Withdraw(_amount0 - balance0);
            }
            if (balance1 < _amount1) {
                _inventory1 = 0; // reuse var to avoid stack too deep. now a flag, 0 means we withdraw from silo0
                _amount1 = balance1 + _silo0Withdraw(_amount1 - balance1);
            }
        }

        // Place some liquidity in Uniswap
        (_amount0, _amount1) = _primary.deposit(
            _primary.liquidityForAmounts(cache.sqrtPriceX96, _amount0, _amount1)
        );

        // Place excess into silos
        Silo.delegate_deposit(silo0, TOKEN0.balanceOf(address(this)));
        Silo.delegate_deposit(silo1, TOKEN1.balanceOf(address(this)));
        console.log(silo0.balanceOf(address(this)));
        console.log(silo1.balanceOf(address(this)));
        packedSlot = PackedSlot(_primary.lower, _primary.upper);
        emit Reposition(_primary.lower, _primary.upper);
    }

    function selfDestruct() external onlyOwner {
        // get primary uni position
        Uniswap.Position memory _primary = _loadPackedSlot();

        // Withdraw all funds from silo0
        Silo.delegate_withdraw(silo0, silo0.balanceOf(address(this)));

        // Withdraw all funds from silo1
        Silo.delegate_withdraw(silo1, silo1.balanceOf(address(this)));

        // Exit primary position
        (uint128 liquidity, , , , ) = _primary.info();
        _primary.withdraw(liquidity);

        // Transfer tokens
        TOKEN0.safeTransfer(msg.sender, TOKEN0.balanceOf(address(this)));
        TOKEN1.safeTransfer(msg.sender, TOKEN1.balanceOf(address(this)));

        // Call self destruct
        selfdestruct(payable(msg.sender));
    }

    // ⬇️⬇️⬇️⬇️ VIEW FUNCTIONS ⬇️⬇️⬇️⬇️  ------------------------------------------------------------------------------

    function _priceX96FromTick(int24 _tick) internal pure returns (uint256) {
        uint256 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(_tick);
        return FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, Q96);
    }

    function _targetTokenRatioD(
        int24 tick,
        int24 tickMin,
        int24 tickMax
    ) internal pure returns (uint256) {
        if (tick <= tickMin) {
            return 0;
        }
        if (tick >= tickMax) {
            return DENOMINATOR;
        }
        return
            (uint256(uint24(tickMax - tick)) * DENOMINATOR) /
            uint256(uint24(tickMax - tickMin));
    }

    function _loadPackedSlot() private view returns (Uniswap.Position memory) {
        PackedSlot memory _packedSlot = packedSlot;
        return (
            Uniswap.Position(
                UNI_POOL,
                _packedSlot.primaryLower,
                _packedSlot.primaryUpper
            )
        );
    }

    function getInventory()
        external
        view
        returns (uint256 inventory0, uint256 inventory1)
    {
        Uniswap.Position memory primary = _loadPackedSlot();
        (uint160 sqrtPriceX96, , , , , , ) = UNI_POOL.slot0();
        (inventory0, inventory1) = _getInventory(primary, sqrtPriceX96);
    }

    function getSharePriceInToken0()
        external
        view
        returns (uint256 sharePrice)
    {
        Uniswap.Position memory primary = _loadPackedSlot();
        (uint160 sqrtPriceX96, int24 tick, , , , , ) = UNI_POOL.slot0();
        (uint256 inventory0, uint256 inventory1) = _getInventory(
            primary,
            sqrtPriceX96
        );
        // calculate inventory1 in terms of token 0
        uint256 priceX96 = _priceX96FromTick(tick);
        uint256 inventory1InToken0 = FullMath.mulDiv(inventory1, Q96, priceX96);
        sharePrice = (inventory1InToken0 + inventory0) / totalSupply;
    }

    function canRebalance() external view returns (bool) {
        Uniswap.Position memory primary = _loadPackedSlot();

        // Populate rebalance cache
        RebalanceCache memory cache;
        (cache.sqrtPriceX96, cache.tick, , , , , ) = UNI_POOL.slot0();
        cache.priceX96 = uint224(
            FullMath.mulDiv(cache.sqrtPriceX96, cache.sqrtPriceX96, Q96)
        );

        // Check inventory
        (uint256 inventory0, uint256 inventory1) = _getInventory(
            primary,
            cache.sqrtPriceX96
        );
        console.log(inventory0, inventory1);

        // Compute inventory ratio to determine what happens next
        uint256 ratio = FullMath.mulDiv(
            10_000,
            inventory0,
            inventory0 + FullMath.mulDiv(inventory1, Q96, cache.priceX96)
        );
        // Compute target ratio to determine what happens next
        uint256 _targetRatioD = _targetTokenRatioD(
            cache.tick,
            MIN_TICK,
            MAX_TICK
        );
        // if inventory ratio deviates by 2 percent of the target ratio rebalance.
        uint256 lowerBound = FullMath.mulDiv(_targetRatioD, 9800, DENOMINATOR);
        uint256 upperBound = FullMath.mulDiv(_targetRatioD, 10200, DENOMINATOR);
        return (ratio < lowerBound || ratio > upperBound);
    }

    function canReposition() external view returns (bool) {
        // Get uni position
        Uniswap.Position memory _primary = _loadPackedSlot();
        (, int24 tick, , , , , ) = UNI_POOL.slot0();
        // Check to make sure that tick is out of current sub range and in larger range.
        return (tick > _primary.upper || tick < _primary.lower);
    }

    struct InventoryDetails {
        // The amount of token0 available to limit order, i.e. everything *not* in the primary position
        uint256 fluid0;
        // The amount of token1 available to limit order, i.e. everything *not* in the primary position
        uint256 fluid1;
        // The liquidity present in the primary position. Note that this may be higher than what the
        // vault deposited since someone may designate this contract as a `mint()` recipient
        uint128 primaryLiquidity;
    }

    /*
     * @notice Estimate's the vault's liabilities to users -- in other words, how much would be paid out if all
     * holders redeemed their LP tokens at once.
     * @dev Underestimates the true payout unless both silos and Uniswap positions have just been poked.
     * @param _primary The primary position
     * @param _sqrtPriceX96 The current sqrt(price) of the Uniswap pair from `slot0()`
     * @return inventory0 The amount of token0 underlying all LP tokens
     * @return inventory1 The amount of token1 underlying all LP tokens
     */
    function _getInventory(
        Uniswap.Position memory _primary,
        uint160 _sqrtPriceX96
    ) private view returns (uint256 inventory0, uint256 inventory1) {
        uint256 a;
        uint256 b;
        uint128 liquidity;
        // token0 from silo0
        inventory0 = silo0.balanceOf(address(this));

        // token1 from silo1
        inventory1 = silo1.balanceOf(address(this));

        // Primary position
        if (_primary.lower != _primary.upper) {
            (liquidity, , , a, b) = _primary.info();
            (uint256 amount0, uint256 amount1) = _primary.amountsForLiquidity(
                _sqrtPriceX96,
                liquidity
            );

            inventory0 += amount0 + a;
            inventory1 += amount1 + b;
        }
    }

    // ⬆️⬆️⬆️⬆️ VIEW FUNCTIONS ⬆️⬆️⬆️⬆️  ------------------------------------------------------------------------------
    // ⬇️⬇️⬇️⬇️ PURE FUNCTIONS ⬇️⬇️⬇️⬇️  ------------------------------------------------------------------------------

    /**
     * @notice Attempts to withdraw `_amount` from silo0. If `_amount` is more than what's available, withdraw the
     * maximum amount.
     * @dev This reads and writes from/to `maintenanceBudget0`, so use sparingly
     * @param _amount The desired amount of token0 to withdraw from silo0
     * @return uint256 The actual amount of token0 that was withdrawn
     */
    function _silo0Withdraw(uint256 _amount) private returns (uint256) {
        unchecked {
            uint256 b = silo0.balanceOf(address(this));
            if (_amount > b) _amount = b;
            Silo.delegate_withdraw(silo0,_amount);
            return _amount;
        }
    }

    /**
     * @notice Attempts to withdraw `_amount` from silo1. If `_amount` is more than what's available, withdraw the
     * maximum amount.
     * @dev This reads and writes from/to `maintenanceBudget1`, so use sparingly
     * @param _amount The desired amount of token1 to withdraw from silo1
     * @return uint256 The actual amount of token1 that was withdrawn
     */
    function _silo1Withdraw(uint256 _amount) private returns (uint256) {
        unchecked {
            uint256 b = silo1.balanceOf(address(this));
            if (_amount > b) _amount = b;
            Silo.delegate_withdraw(silo1, _amount);
            return _amount;
        }
    }

    /// @dev Computes amounts that should be placed in primary Uniswap position to maintain appropriate inventory ratio.
    function _computeUniAmounts(
        uint256 _inventory0,
        uint256 _inventory1,
        int24 _tick,
        int24 _tickLower,
        int24 _tickUpper
    ) internal view returns (uint256 amount0, uint256 amount1) {
        // calculate inventory1 in terms of token 0
        uint256 priceX96 = _priceX96FromTick(_tick);
        uint256 inventory1InToken0 = FullMath.mulDiv(
            _inventory1,
            Q96,
            priceX96
        );
        // the fraction of total inventory (X96) that should be put into primary Uniswap
        uint256 targetUniInToken0 = FullMath.mulDiv(
            inventory1InToken0 + _inventory0,
            targetUniRatioD,
            DENOMINATOR
        );
        uint256 ratioD = _targetTokenRatioD(_tick, _tickLower, _tickUpper);
        amount0 = FullMath.mulDiv(targetUniInToken0, ratioD, DENOMINATOR);
        amount1 = FullMath.mulDiv(targetUniInToken0 - amount0, priceX96, Q96);
    }

    /// @dev Computes the largest possible `amount0` and `amount1` such that they match the current inventory ratio,
    /// but are not greater than `_amount0Max` and `_amount1Max` respectively. May revert if the following are true:
    ///     _totalSupply * _amount0Max / _inventory0 > type(uint256).max
    ///     _totalSupply * _amount1Max / _inventory1 > type(uint256).max
    /// This is okay because it only blocks deposit (not withdraw). Can also workaround by depositing smaller amounts
    function _computeLPShares(
        uint256 _totalSupply,
        uint256 _inventory0,
        uint256 _inventory1,
        uint256 _amount0Max,
        uint256 _amount1Max,
        uint160 _sqrtPriceX96,
        int24 _tick
    )
        internal
        view
        returns (
            uint256 shares,
            uint256 amount0,
            uint256 amount1
        )
    {
        // If total supply > 0, pool can't be empty
        assert(_totalSupply == 0 || _inventory0 != 0 || _inventory1 != 0);

        if (_totalSupply == 0) {
            // For first deposit, enforce target ratio manually
            uint256 _targetRatioD = _targetTokenRatioD(
                _tick,
                MIN_TICK,
                MAX_TICK
            );
            uint224 priceX96 = uint224(
                FullMath.mulDiv(_sqrtPriceX96, _sqrtPriceX96, Q96)
            );
            amount0 = FullMath.mulDiv(_amount1Max, Q96, priceX96);
            amount0 = DENOMINATOR != _targetRatioD
                ? FullMath.mulDiv(
                    amount0,
                    _targetRatioD,
                    DENOMINATOR - _targetRatioD
                )
                : 0;
            if (amount0 < _amount0Max) {
                amount1 = _amount1Max;
                shares = amount1;
            } else {
                amount0 = _amount0Max;
                amount1 = FullMath.mulDiv(amount0, priceX96, Q96);
                amount1 = FullMath.mulDiv(
                    amount1,
                    DENOMINATOR - _targetRatioD,
                    _targetRatioD
                );
                shares = amount0;
            }
        } else if (_inventory0 == 0) {
            amount1 = _amount1Max;
            shares = FullMath.mulDiv(amount1, _totalSupply, _inventory1);
        } else if (_inventory1 == 0) {
            amount0 = _amount0Max;
            shares = FullMath.mulDiv(amount0, _totalSupply, _inventory0);
        } else {
            // The branches of this ternary are logically identical, but must be separate to avoid overflow
            bool cond = _inventory0 < _inventory1
                ? FullMath.mulDiv(_amount1Max, _inventory0, _inventory1) <
                    _amount0Max
                : _amount1Max <
                    FullMath.mulDiv(_amount0Max, _inventory1, _inventory0);

            if (cond) {
                amount1 = _amount1Max;
                amount0 = FullMath.mulDiv(amount1, _inventory0, _inventory1);
                shares = FullMath.mulDiv(amount1, _totalSupply, _inventory1);
            } else {
                amount0 = _amount0Max;
                amount1 = FullMath.mulDiv(amount0, _inventory1, _inventory0);
                shares = FullMath.mulDiv(amount0, _totalSupply, _inventory0);
            }
        }
    }
}
