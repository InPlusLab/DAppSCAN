// SPDX-License-Identifier: AGPL-3.0-only

/**
 *   ERC20ModuleForMainnet.sol - SKALE Interchain Messaging Agent
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

import "./PermissionsForMainnet.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/ERC20.sol";

interface ILockAndDataERC20M {
    function erc20Tokens(uint256 index) external returns (address);
    function erc20Mapper(address contractERC20) external returns (uint256);
    function addERC20Token(address contractERC20) external returns (uint256);
    function sendERC20(address contractHere, address to, uint256 amount) external returns (bool);
}

/**
 * @title ERC20 Module For Mainnet
 * @dev Runs on Mainnet, and manages receiving and sending of ERC20 token contracts
 * and encoding contractPosition in LockAndDataForMainnetERC20.
 */
contract ERC20ModuleForMainnet is PermissionsForMainnet {

    /**
     * @dev Emitted when token is mapped in LockAndDataForMainnetERC20.
     */
    event ERC20TokenAdded(address indexed tokenHere, uint256 contractPosition);
    
    /**
     * @dev Emitted when token is received by DepositBox and is ready to be cloned
     * or transferred on SKALE chain.
     */
    event ERC20TokenReady(address indexed tokenHere, uint256 contractPosition, uint256 amount);

    /**
     * @dev Allows DepositBox to receive ERC20 tokens.
     * 
     * Emits an {ERC20TokenAdded} event on token mapping in LockAndDataForMainnetERC20.
     * Emits an {ERC20TokenReady} event.
     * 
     * Requirements:
     * 
     * - Amount must be less than or equal to the total supply of the ERC20 contract.
     */
    function receiveERC20(
        address contractHere,
        address to,
        uint256 amount,
        bool isRAW
    )
        external
        allow("DepositBox")
        returns (bytes memory data)
    {
        address lockAndDataERC20 = IContractManagerForMainnet(lockAndDataAddress_).permitted(
            keccak256(abi.encodePacked("LockAndDataERC20"))
        );
        uint256 totalSupply = ERC20UpgradeSafe(contractHere).totalSupply();
        require(amount <= totalSupply, "Amount is incorrect");
        uint256 contractPosition = ILockAndDataERC20M(lockAndDataERC20).erc20Mapper(contractHere);
        if (contractPosition == 0) {
            contractPosition = ILockAndDataERC20M(lockAndDataERC20).addERC20Token(contractHere);
            emit ERC20TokenAdded(contractHere, contractPosition);
        }
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
        emit ERC20TokenReady(contractHere, contractPosition, amount);
        return data;
    }

    /**
     * @dev Allows DepositBox to send ERC20 tokens.
     */
    function sendERC20(address to, bytes calldata data) external allow("DepositBox") returns (bool) {
        address lockAndDataERC20 = IContractManagerForMainnet(lockAndDataAddress_).permitted(
            keccak256(abi.encodePacked("LockAndDataERC20"))
        );
        uint256 contractPosition;
        address contractAddress;
        address receiver;
        uint256 amount;
        (contractPosition, receiver, amount) = _fallbackDataParser(data);
        contractAddress = ILockAndDataERC20M(lockAndDataERC20).erc20Tokens(contractPosition);
        if (to != address(0)) {
            if (contractAddress == address(0)) {
                contractAddress = to;
            }
        }
        bool variable = ILockAndDataERC20M(lockAndDataERC20).sendERC20(contractAddress, receiver, amount);
        return variable;
    }

    /**
     * @dev Returns the receiver address of the ERC20 token.
     */
    function getReceiver(bytes calldata data) external view returns (address receiver) {
        uint256 contractPosition;
        uint256 amount;
        (contractPosition, receiver, amount) = _fallbackDataParser(data);
    }

    function initialize(address newLockAndDataAddress) public override initializer {
        PermissionsForMainnet.initialize(newLockAndDataAddress);
    }

    /**
     * @dev Returns encoded creation data for ERC20 token.
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

}
