// Copyright (C) 2021 BITFISH LIMITED

// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

// SPDX-License-Identifier: GPL-3.0-only

pragma solidity 0.8.4;

/// @dev https://eips.ethereum.org/EIPS/eip-1167
contract ProxyFactory {
    function _getDeterministicAddress(
        address target,
        bytes32 salt
    ) internal view returns (address proxy) {
        address deployer = address(this);
        assembly {
            let clone := mload(0x40)
            mstore(clone, 0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000)
            mstore(add(clone, 0x14), shl(0x60, target))
            mstore(add(clone, 0x28), 0x5af43d82803e903d91602b57fd5bf3ff00000000000000000000000000000000)
            mstore(add(clone, 0x38), shl(0x60, deployer))
            mstore(add(clone, 0x4c), salt)
            mstore(add(clone, 0x6c), keccak256(clone, 0x37))
            proxy := keccak256(add(clone, 0x37), 0x55)
        }
    }

    function _createProxyDeterministic(
        address target,
        bytes memory initData,
        bytes32 salt
    ) internal returns (address proxy) {
        assembly {
            let clone := mload(0x40)
            mstore(clone, 0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000)
            mstore(add(clone, 0x14), shl(0x60, target))
            mstore(add(clone, 0x28), 0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000)
            proxy := create2(0, clone, 0x37, salt)
        }
        require(proxy != address(0), "Proxy deploy failed");

        if (initData.length > 0) {
            (bool success, ) = proxy.call(initData);
            require(success, "Proxy init failed");
        }
    }
}
