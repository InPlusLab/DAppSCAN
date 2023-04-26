// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { GoodAddressDeployer } from '../libraries/GoodAddressDeployer.sol';

contract GoodAddressDeployerTest {
    receive() external payable {}

    event Address(address val);

    function deploy(uint256 amount, bytes memory bytecode) external returns (address computed) {
        computed = GoodAddressDeployer.deploy(amount, bytecode, _isAddressGood);
        emit Address(computed);
    }

    // to be overriden using smock
    function isAddressGood(address) external pure returns (bool) {
        return false;
    }

    function _isAddressGood(address input) internal view returns (bool) {
        return this.isAddressGood(input);
    }
}
