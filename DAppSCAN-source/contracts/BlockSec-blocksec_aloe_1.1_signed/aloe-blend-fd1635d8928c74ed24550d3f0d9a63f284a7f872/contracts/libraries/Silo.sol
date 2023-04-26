// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Address.sol";

import "../interfaces/ISilo.sol";

library Silo {
    using Address for address;

    function delegate_poke(ISilo silo) internal {
        address(silo).functionDelegateCall(abi.encodeWithSelector(silo.poke.selector));
    }

    function delegate_deposit(ISilo silo, uint256 amount) internal {
        address(silo).functionDelegateCall(abi.encodeWithSelector(silo.deposit.selector, amount));
    }

    function delegate_withdraw(ISilo silo, uint256 amount) internal {
        address(silo).functionDelegateCall(abi.encodeWithSelector(silo.withdraw.selector, amount));
    }
}
