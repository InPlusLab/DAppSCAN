// SPDX-License-Identifier: AGPL-3.0-only

/**
 *   ERC721ModuleForSchain.sol - SKALE Interchain Messaging Agent
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
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC721/IERC721Metadata.sol";

interface ITokenFactoryForERC721 {
    function createERC721(string memory name, string memory symbol)
        external
        returns (address payable);
}

interface ILockAndDataERC721S {
    function erc721Tokens(uint256 index) external returns (address);
    function erc721Mapper(address contractERC721) external returns (uint256);
    function addERC721Token(address contractERC721, uint256 contractPosition) external;
    function sendERC721(address contractHere, address to, uint256 tokenId) external returns (bool);
    function receiveERC721(address contractHere, uint256 tokenId) external returns (bool);
}


contract ERC721ModuleForSchain is PermissionsForSchain {

    event ERC721TokenCreated(uint256 indexed contractPosition, address tokenAddress);


    constructor(address newLockAndDataAddress) public PermissionsForSchain(newLockAndDataAddress) {
        // solhint-disable-previous-line no-empty-blocks
    }

    /**
     * @dev Allows TokenManager to receive ERC721 tokens.
     * 
     * Requirements:
     * 
     * - ERC721 token contract must exist in LockAndDataForSchainERC721.
     * - ERC721 token must be received by LockAndDataForSchainERC721.
     */
    function receiveERC721(
        address contractHere,
        address to,
        uint256 tokenId,
        bool isRAW) external allow("TokenManager") returns (bytes memory data)
        {
        address lockAndDataERC721 = IContractManagerForSchain(getLockAndDataAddress()).
            permitted(keccak256(abi.encodePacked("LockAndDataERC721")));
        if (!isRAW) {
            uint256 contractPosition = ILockAndDataERC721S(lockAndDataERC721).erc721Mapper(contractHere);
            require(contractPosition > 0, "ERC721 contract does not exist on SKALE chain");
            require(
                ILockAndDataERC721S(lockAndDataERC721).receiveERC721(contractHere, tokenId),
                "Could not receive ERC721 Token"
            );
            data = _encodeData(
                contractHere,
                contractPosition,
                to,
                tokenId);
            return data;
        } else {
            data = _encodeRawData(to, tokenId);
            return data;
        }
    }

    /**
     * @dev Allows TokenManager to send ERC721 tokens.
     *  
     * Emits a {ERC721TokenCreated} event if to address = 0.
     */
    function sendERC721(address to, bytes calldata data) external allow("TokenManager") returns (bool) {
        address lockAndDataERC721 = IContractManagerForSchain(getLockAndDataAddress()).
            permitted(keccak256(abi.encodePacked("LockAndDataERC721")));
        uint256 contractPosition;
        address contractAddress;
        address receiver;
        uint256 tokenId;
        if (to == address(0)) {
            (contractPosition, receiver, tokenId) = _fallbackDataParser(data);
            contractAddress = ILockAndDataERC721S(lockAndDataERC721).erc721Tokens(contractPosition);
            if (contractAddress == address(0)) {
                contractAddress = _sendCreateERC721Request(data);
                emit ERC721TokenCreated(contractPosition, contractAddress);
                ILockAndDataERC721S(lockAndDataERC721).addERC721Token(contractAddress, contractPosition);
            }
        } else {
            (receiver, tokenId) = _fallbackRawDataParser(data);
            contractAddress = to;
        }
        return ILockAndDataERC721S(lockAndDataERC721).sendERC721(contractAddress, receiver, tokenId);
    }

    /**
     * @dev Returns the receiver address.
     */
    function getReceiver(address to, bytes calldata data) external pure returns (address receiver) {
        uint256 contractPosition;
        uint256 tokenId;
        if (to == address(0)) {
            (contractPosition, receiver, tokenId) = _fallbackDataParser(data);
        } else {
            (receiver, tokenId) = _fallbackRawDataParser(data);
        }
    }

    function _sendCreateERC721Request(bytes calldata data) internal returns (address) {
        string memory name;
        string memory symbol;
        (name, symbol) = _fallbackDataCreateERC721Parser(data);
        address tokenFactoryAddress = IContractManagerForSchain(
            getLockAndDataAddress()
        ).permitted(keccak256(abi.encodePacked("TokenFactory")));
        return ITokenFactoryForERC721(tokenFactoryAddress).createERC721(name, symbol);
    }

    /**
     * @dev Returns encoded creation data.
     */
    function _encodeData(
        address contractHere,
        uint256 contractPosition,
        address to,
        uint256 tokenId
    )
        private
        view
        returns (bytes memory data)
    {
        string memory name = IERC721Metadata(contractHere).name();
        string memory symbol = IERC721Metadata(contractHere).symbol();
        data = abi.encodePacked(
            bytes1(uint8(5)),
            bytes32(contractPosition),
            bytes32(bytes20(to)),
            bytes32(tokenId),
            bytes(name).length,
            name,
            bytes(symbol).length,
            symbol
        );
    }

    /**
     * @dev Returns encoded raw data.
     */
    function _encodeRawData(address to, uint256 tokenId) private pure returns (bytes memory data) {
        data = abi.encodePacked(
            bytes1(uint8(21)),
            bytes32(bytes20(to)),
            bytes32(tokenId)
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

    /**
     * @dev Returns fallback data.
     */
    function _fallbackRawDataParser(bytes memory data)
        private
        pure
        returns (address payable, uint256)
    {
        bytes32 to;
        bytes32 token;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            to := mload(add(data, 33))
            token := mload(add(data, 65))
        }
        return (address(bytes20(to)), uint256(token));
    }

    function _fallbackDataCreateERC721Parser(bytes memory data)
        private
        pure
        returns (
            string memory name,
            string memory symbol
        )
    {
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
    }
}


