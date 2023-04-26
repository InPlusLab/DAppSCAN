// SPDX-License-Identifier: AGPL-3.0-only

/*
    ProxyFactoryMock.sol - SKALE SAFT Core
    Copyright (C) 2018-Present SKALE Labs
    @author Dmytro Stebaiev

    SKALE SAFT Core is free software: you can redistribute it and/or modify
    it under the terms of the GNU Affero General Public License as published
    by the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    SKALE SAFT Core is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU Affero General Public License for more details.

    You should have received a copy of the GNU Affero General Public License
    along with SKALE SAFT Core.  If not, see <https://www.gnu.org/licenses/>.
*/

pragma solidity 0.6.10;

import "../interfaces/openzeppelin/IProxyFactory.sol";
import "../interfaces/openzeppelin/IProxyAdmin.sol";


contract ProxyMock {
    bytes32 internal constant _IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    constructor(address implementation, bytes memory _data) public {
        _setImplementation(implementation);
        if(_data.length > 0) {
            // solhint-disable-next-line avoid-low-level-calls
            (bool success,) = implementation.delegatecall(_data);
            require(success);
        }
    }

    fallback () payable external {
        _delegate(_implementation());
    }

    function _delegate(address implementation) internal {
        // solhint-disable-next-line no-inline-assembly
        assembly {
        // Copy msg.data. We take full control of memory in this inline assembly
        // block because it will not return to Solidity code. We overwrite the
        // Solidity scratch pad at memory position 0.
        calldatacopy(0, 0, calldatasize())

        // Call the implementation.
        // out and outsize are 0 because we don't know the size yet.
        let result := delegatecall(gas(), implementation, 0, calldatasize(), 0, 0)

        // Copy the returned data.
        returndatacopy(0, 0, returndatasize())

        switch result
        // delegatecall returns 0 on error.
        case 0 { revert(0, returndatasize()) }
        default { return(0, returndatasize()) }
        }
    }

    function _implementation() internal view returns (address impl) {
        bytes32 slot = _IMPLEMENTATION_SLOT;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            impl := sload(slot)
        }
    }
    
    function _setImplementation(address newImplementation) internal {
        bytes32 slot = _IMPLEMENTATION_SLOT;

        // solhint-disable-next-line no-inline-assembly
        assembly {
            sstore(slot, newImplementation)
        }
    }
}

contract ProxyFactoryMock is IProxyFactory, IProxyAdmin {
    address public implementation;
    function deploy(uint256, address _logic, address, bytes memory _data) external override returns (address) {
        return address(new ProxyMock(_logic, _data));
    }
    function setImplementation(address _implementation) external {
        implementation = _implementation;
    }
    function getProxyImplementation(address) external view override returns (address) {
        return implementation;
    }    
}