// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;
import "./ISwapSweepEvents.sol";

// solhint-disable no-empty-blocks
/// @title Aloe Blend vault interface
/// @dev The interface is broken up into many smaller pieces
interface ISwapSweep is ISwapSweepEvents {
    function setMaxDeadline(uint256 _deadline) external;

    function setMaxSlippageD(uint256 _maxSlippageD) external;

    /**
     * @notice Deposits tokens in proportion to the vault's current holdings
     * @param amount0Max Max amount of TOKEN0 to deposit
     * @param amount1Max Max amount of TOKEN1 to deposit
     * @param amount0Min Ensure `amount0` is greater than this
     * @param amount1Min Ensure `amount1` is greater than this
     * @param investorId id of the investor we are depositing on behalf for.
     * @return shares Number of shares minted
     * @return amount0 Amount of TOKEN0 deposited
     * @return amount1 Amount of TOKEN1 deposited
     */
    function deposit(
        uint256 amount0Max,
        uint256 amount1Max,
        uint256 amount0Min,
        uint256 amount1Min,
        uint256 investorId
    )
        external
        returns (
            uint256 shares,
            uint256 amount0,
            uint256 amount1
        );

    /**
     * @notice Withdraws tokens in proportion to the vault's current holdings
     * @param shares Shares burned by sender
     * @param amount0Min Revert if resulting `amount0` is smaller than this
     * @param amount1Min Revert if resulting `amount1` is smaller than this
     * @param investorId id of the investor we are depositing on behalf for.
     * @return amount0 Amount of token0 sent to recipient
     * @return amount1 Amount of token1 sent to recipient
     */
    function withdraw(
        uint256 shares,
        uint256 amount0Min,
        uint256 amount1Min,
        uint256 investorId
    ) external returns (uint256 amount0, uint256 amount1);

    /**
     * @notice function called by Gelato resolver contract to determine when to execute rebalance transaction.
     */
    function canRebalance() external view returns (bool);

    /**
     * @notice Rebalances vault to maintain target inventory ratio
     * @param _deadline is unix time aloted execute swap needed reach target ratio
     */
    function rebalance(uint256 _deadline) external;

    /**
     * @notice function called by Gelato resolver contract to determine when to execute reposition transaction.
     */
    function canReposition() external view returns (bool);

    /**
     * @notice Repositions uni position to the adjacent subrange that the price crossed into
     */
    function reposition() external;

    /**
     * @notice Withdraws all funds managed by SwapSweep and sends them to admin,
      this includes the captial from the silos and uni positions. Then the contract self destructs.
     */
    function selfDestruct() external;

    /**
     * @notice Returns the total capital managaed by SwapSweep.
     * @return inventory0 The amount of token0 underlying all shares
     * @return inventory1 The amount of token1 underlying all shares
     */
    function getInventory()
        external
        view
        returns (uint256 inventory0, uint256 inventory1);

    /**
     * @return sharePrice the price of one SwapSweep vault share in token0 (USDC)
     */
    function getSharePriceInToken0() external view returns (uint256 sharePrice);
}
