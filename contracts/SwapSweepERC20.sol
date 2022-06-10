// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.10;

import "@rari-capital/solmate/src/tokens/ERC20.sol";

contract SwapSweepERC20 is ERC20 {
    // solhint-disable no-empty-blocks
    mapping(uint256 => uint256) public shares;

    constructor(string memory _name) ERC20(_name, "SWAP_SWEEP", 18) {}

    function _mint(
        address to,
        uint256 investorId,
        uint256 amount
    ) internal {
        totalSupply += amount;

        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            balanceOf[to] += amount;
            shares[investorId] += amount;
        }

        emit Transfer(address(0), to, amount);
    }

    function _burn(
        address from,
        uint256 investorId,
        uint256 amount
    ) internal {
        balanceOf[from] -= amount;
        shares[investorId] -= amount;
        // Cannot underflow because a user's balance
        // will never be larger than the total supply.
        unchecked {
            totalSupply -= amount;
        }

        emit Transfer(from, address(0), amount);
    }
}
