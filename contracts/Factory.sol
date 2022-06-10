// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.10;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import "./SwapSweep.sol";
import "./interfaces/IFactory.sol";
import "./interfaces/ISilo.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

import "./helpers/BaseSplitCodeFactory.sol";

contract Factory is BaseSplitCodeFactory, IFactory {
    event CreateVault(SwapSweep indexed vault);

    /// @inheritdoc IFactory
    mapping(IUniswapV3Pool => mapping(ISilo => mapping(ISilo => SwapSweep)))
        public getVault;

    /// @inheritdoc IFactory
    mapping(SwapSweep => bool) public didCreateVault;

    /// @dev `_creationCode` should equal `type(AloeBlend).creationCode`
    constructor(bytes memory _creationCode)
        BaseSplitCodeFactory(_creationCode)
    {}

    function createVault(
        IUniswapV3Pool pool,
        ISwapRouter _router,
        ISilo silo0,
        ISilo silo1,
        int24 _minTick,
        int24 _maxTick,
        int24 _subDivisions
    ) external returns (SwapSweep vault) {
        bytes memory constructorArgs = abi.encode(
            pool,
            _router,
            silo0,
            silo1,
            _minTick,
            _maxTick,
            _subDivisions
        ); /// @notice Explain to an end user what this does
        /// @dev Explain to a developer any extra details
        /// @return Documents the return variables of a contract’s function state variable
        /// @inheritdoc	Copies all missing tags from the base function (must be followed by the contract name));
        bytes32 salt = keccak256(
            abi.encode(
                pool,
                _router,
                silo0,
                silo1,
                _minTick,
                _maxTick,
                _subDivisions
            )
        );
        vault = SwapSweep(payable(super._create(constructorArgs, salt)));

        getVault[pool][silo0][silo1] = vault;
        didCreateVault[vault] = true;

        emit CreateVault(vault);
    }
}
