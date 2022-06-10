// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "../SwapSweep.sol";
import "./ISilo.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

interface IFactory {
    /// @notice Reports the vault's address (if one exists for the chosen parameters)
    function getVault(
        IUniswapV3Pool pool,
        ISilo silo0,
        ISilo silo1
    ) external view returns (SwapSweep);

    /// @notice Reports whether the given vault was deployed by this factory
    function didCreateVault(SwapSweep vault) external view returns (bool);

    /// @notice Creates a new Blend vault for the given pool + silo combination
    function createVault(
        IUniswapV3Pool pool,
        ISwapRouter _router,
        ISilo silo0,
        ISilo silo1,
        int24 _minTick,
        int24 _maxTick,
        int24 _subDivisions
    ) external returns (SwapSweep);
}
