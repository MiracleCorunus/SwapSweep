// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

interface ISwapSweepEvents {
    /**
     * @notice Emitted every time someone deposits to the vault
     * @param sender The address that deposited to the vault
     * @param investorId The id of the investors funds deposited to the vault
     * @param shares The shares that were minted and sent to `sender`
     * @param amount0 The amount of token0 that `sender` paid in exchange for `shares`
     * @param amount1 The amount of token1 that `sender` paid in exchange for `shares`
     */
    event Deposit(
        address indexed sender,
        uint256 investorId,
        uint256 shares,
        uint256 amount0,
        uint256 amount1
    );

    /**
     * @notice Emitted every time someone withdraws from the vault
     * @param sender The address that withdrew from the vault
     * @param shares The shares that were taken from `sender` and burned
     * @param amount0 The amount of token0 that `sender` received in exchange for `shares`
     * @param amount1 The amount of token1 that `sender` received in exchange for `shares`
     */
    event Withdraw(
        address indexed sender,
        uint256 investorId,
        uint256 shares,
        uint256 amount0,
        uint256 amount1
    );

    /**
     * @notice Emitted every time the vault is rebalanced. Contains general vault data.
     * @param ratio The ratio of value held as token0 to total value,
     * i.e. `inventory0 / (inventory0 + inventory1 / price)`
     * @param shares The total outstanding shares held by depositers
     * @param inventory0 The amount of token0 underlying all shares
     * @param inventory1 The amount of token1 underlying all shares
     */
    event Rebalance(
        uint256 ratio,
        uint256 shares,
        uint256 inventory0,
        uint256 inventory1
    );

    /**
     * @notice Emitted every time the primary Uniswap position is repositioned
     * @param lower The lower bound of the new primary Uniswap position
     * @param upper The upper bound of the new primary Uniswap position
     */
    event Reposition(int24 lower, int24 upper);
}
