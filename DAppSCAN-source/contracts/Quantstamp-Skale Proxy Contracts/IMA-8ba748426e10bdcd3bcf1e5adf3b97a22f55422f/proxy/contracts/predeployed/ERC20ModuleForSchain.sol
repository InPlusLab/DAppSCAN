// SPDX-License-Identifier: AGPL-3.0-only

/**
 *   ERC20ModuleForSchain.sol - SKALE Interchain Messaging Agent
 *   Copyright (C) 2019-Present SKALE Labs
 *   @author Artem Payvin
 *
 *   SKALE IMA is free software: you can redistribute it and/or modify
 *   it under the terms of the GNU Affero General Public License as published
 *   by the Free Software Foundation, either version 3 of the License, or
 *   (at your option) any later version.
 *
 *   SKALE IMA is distributed in the hope that it will be useful,
 *   but WITHOUT ANY WARRANTY; without even the implied warranty of
 *   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *   GNU Affero General Public License for more details.
 *
 *   You should have received a copy of the GNU Affero General Public License
 *   along with SKALE IMA.  If not, see <https://www.gnu.org/licenses/>.
 */

pragma solidity 0.6.12;

import "./PermissionsForSchain.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/ERC20.sol";

interface ITokenFactoryForERC20 {
    function createERC20(string memory name, string memory symbol, uint256 totalSupply)
        external
        returns (address payable);
}

interface ILockAndDataERC20S {
    function erc20Tokens(uint256 index) external returns (address);
    function erc20Mapper(address contractERC20) external returns (uint256);
    function addERC20Token(address contractERC20, uint256 contractPosition) external;
    function sendERC20(address contractHere, address to, uint256 amount) external returns (bool);
    function receiveERC20(address contractHere, uint256 amount) external returns (bool);
}

interface ERC20Clone {
    function setTotalSupplyOnMainnet(uint256 newTotalSupply) external;
    function totalSupplyOnMainnet() external view returns (uint256);
}

/**
 * @title ERC20 Module For SKALE Chain
 * @dev Runs on SKALE Chains and manages ERC20 token contracts for TokenManager.
 */
contract ERC20ModuleForSchain is PermissionsForSchain {

    event ERC20TokenCreated(uint256 indexed contractPosition, address tokenThere);
    event ERC20TokenReceived(uint256 indexed contractPosition, address tokenThere, uint256 amount);


    constructor(address newLockAndDataAddress) public PermissionsForSchain(newLockAndDataAddress) {
        // solhint-disable-previous-line no-empty-blocks
    }

    /**
     * @dev Allows TokenManager to receive ERC20 tokens.
     * 
     * Requirements:
     * 
     * - ERC20 token contract must exist in LockAndDataForSchainERC20.
     * - ERC20 token must be received by LockAndDataForSchainERC20.
     */
    function receiveERC20(
        address contractHere,
        address to,
        uint256 amount,
        bool isRAW) external allow("TokenManager") returns (bytes memory data)
        {
        address lockAndDataERC20 = IContractManagerForSchain(
            getLockAndDataAddress()
        ).permitted(keccak256(abi.encodePacked("LockAndDataERC20")));
        uint256 contractPosition = ILockAndDataERC20S(lockAndDataERC20).erc20Mapper(contractHere);
        require(contractPosition > 0, "ERC20 contract does not exist on SKALE chain.");
        require(
            ILockAndDataERC20S(lockAndDataERC20).receiveERC20(contractHere, amount),
            "Cound not receive ERC20 Token"
        );
        if (!isRAW) {
            data = _encodeCreationData(
                contractHere,
                contractPosition,
                to,
                amount
            );
        } else {
            data = _encodeRegularData(to, contractPosition, amount);
        }
        return data;
    }

    /**
     * @dev Allows TokenManager to send ERC20 tokens.
     *  
     * Emits a {ERC20TokenCreated} event if token does not exist.
     * Emits a {ERC20TokenReceived} event on success.
     */
    function sendERC20(address to, bytes calldata data) external allow("TokenManager") returns (bool) {
        address lockAndDataERC20 = IContractManagerForSchain(
            getLockAndDataAddress()
        ).permitted(keccak256(abi.encodePacked("LockAndDataERC20")));
        uint256 contractPosition;
        address contractAddress;
        address receiver;
        uint256 amount;
        (contractPosition, receiver, amount) = _fallbackDataParser(data);
        contractAddress = ILockAndDataERC20S(lockAndDataERC20).erc20Tokens(contractPosition);
        if (to == address(0)) {
            if (contractAddress == address(0)) {
                contractAddress = _sendCreateERC20Request(data);
                emit ERC20TokenCreated(contractPosition, contractAddress);
                ILockAndDataERC20S(lockAndDataERC20).addERC20Token(contractAddress, contractPosition);
            } else {
                uint256 totalSupply = _fallbackTotalSupplyParser(data);
                if (totalSupply > ERC20Clone(contractAddress).totalSupplyOnMainnet()) {
                    ERC20Clone(contractAddress).setTotalSupplyOnMainnet(totalSupply);
                }
            }
            emit ERC20TokenReceived(contractPosition, contractAddress, amount);
        } else {
            if (contractAddress == address(0)) {
                ILockAndDataERC20S(lockAndDataERC20).addERC20Token(to, contractPosition);
                contractAddress = to;
            }
            emit ERC20TokenReceived(0, contractAddress, amount);
        }
        return ILockAndDataERC20S(lockAndDataERC20).sendERC20(contractAddress, receiver, amount);
    }

    /**
     * @dev Returns the receiver address.
     */
    function getReceiver(bytes calldata data) external view returns (address receiver) {
        uint256 contractPosition;
        uint256 amount;
        (contractPosition, receiver, amount) = _fallbackDataParser(data);
    }

    function _sendCreateERC20Request(bytes calldata data) internal returns (address) {
        string memory name;
        string memory symbol;
        uint256 totalSupply;
        (name, symbol, , totalSupply) = _fallbackDataCreateERC20Parser(data);
        address tokenFactoryAddress = IContractManagerForSchain(
            getLockAndDataAddress()
        ).permitted(keccak256(abi.encodePacked("TokenFactory")));
        return ITokenFactoryForERC20(tokenFactoryAddress).createERC20(name, symbol, totalSupply);
    }

    /**
     * @dev Returns encoded creation data.
     */
    function _encodeCreationData(
        address contractHere,
        uint256 contractPosition,
        address to,
        uint256 amount
    )
        private
        view
        returns (bytes memory data)
    {
        string memory name = ERC20UpgradeSafe(contractHere).name();
        uint8 decimals = ERC20UpgradeSafe(contractHere).decimals();
        string memory symbol = ERC20UpgradeSafe(contractHere).symbol();
        uint256 totalSupply = ERC20UpgradeSafe(contractHere).totalSupply();
        data = abi.encodePacked(
            bytes1(uint8(3)),
            bytes32(contractPosition),
            bytes32(bytes20(to)),
            bytes32(amount),
            bytes(name).length,
            name,
            bytes(symbol).length,
            symbol,
            decimals,
            totalSupply
        );
    }

    /**
     * @dev Returns encoded regular data.
     */
    function _encodeRegularData(
        address to,
        uint256 contractPosition,
        uint256 amount
    )
        private
        pure
        returns (bytes memory data)
    {
        data = abi.encodePacked(
            bytes1(uint8(19)),
            bytes32(contractPosition),
            bytes32(bytes20(to)),
            bytes32(amount)
        );
    }

    /**
     * @dev Returns fallback total supply data.
     */
    function _fallbackTotalSupplyParser(bytes memory data)
        private
        pure
        returns (uint256)
    {
        bytes32 totalSupply;
        bytes32 nameLength;
        bytes32 symbolLength;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            nameLength := mload(add(data, 129))
        }
        uint256 lengthOfName = uint256(nameLength);
        // solhint-disable-next-line no-inline-assembly
        assembly {
            symbolLength := mload(add(data, add(161, lengthOfName)))
        }
        uint256 lengthOfSymbol = uint256(symbolLength);
        // solhint-disable-next-line no-inline-assembly
        assembly {
            totalSupply := mload(add(data,
                add(194, add(lengthOfName, lengthOfSymbol))))
        }
        return uint256(totalSupply);
    }

    /**
     * @dev Returns fallback data.
     */
    function _fallbackDataParser(bytes memory data)
        private
        pure
        returns (uint256, address payable, uint256)
    {
        bytes32 contractIndex;
        bytes32 to;
        bytes32 token;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            contractIndex := mload(add(data, 33))
            to := mload(add(data, 65))
            token := mload(add(data, 97))
        }
        return (
            uint256(contractIndex), address(bytes20(to)), uint256(token)
        );
    }

    function _fallbackDataCreateERC20Parser(bytes memory data)
        private
        pure
        returns (
            string memory name,
            string memory symbol,
            uint8,
            uint256
        )
    {
        bytes1 decimals;
        bytes32 totalSupply;
        bytes32 nameLength;
        bytes32 symbolLength;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            nameLength := mload(add(data, 129))
        }
        name = new string(uint256(nameLength));
        for (uint256 i = 0; i < uint256(nameLength); i++) {
            bytes(name)[i] = data[129 + i];
        }
        uint256 lengthOfName = uint256(nameLength);
        // solhint-disable-next-line no-inline-assembly
        assembly {
            symbolLength := mload(add(data, add(161, lengthOfName)))
        }
        symbol = new string(uint256(symbolLength));
        for (uint256 i = 0; i < uint256(symbolLength); i++) {
            bytes(symbol)[i] = data[161 + lengthOfName + i];
        }
        uint256 lengthOfSymbol = uint256(symbolLength);
        // solhint-disable-next-line no-inline-assembly
        assembly {
            decimals := mload(add(data,
                add(193, add(lengthOfName, lengthOfSymbol))))
            totalSupply := mload(add(data,
                add(194, add(lengthOfName, lengthOfSymbol))))
        }
        return (
            name,
            symbol,
            uint8(decimals),
            uint256(totalSupply)
            );
    }
}
