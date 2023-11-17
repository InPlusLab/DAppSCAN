// SPDX-License-Identifier: MIT

pragma solidity 0.6.9;

import "../extensions/IAmpTokensSender.sol";
import "../erc1820/ERC1820Implementer.sol";


contract MockAmpTokensSender is IAmpTokensSender, ERC1820Implementer {
    string internal constant AMP_TOKENS_SENDER = "AmpTokensSender";

    // Default sender hook failure data for the mock only
    bytes32 internal constant _TRANSFER_REVERT = 0x1100000000000000000000000000000000000000000000000000000000000000;

    constructor() public {
        ERC1820Implementer._setInterface(AMP_TOKENS_SENDER);
    }

    function canTransfer(
        bytes4, /*functionSig*/
        bytes32, /*partition*/
        address, /*operator*/
        address from,
        address to,
        uint256 value,
        bytes calldata data,
        bytes calldata // Comments to avoid compilation warnings for unused variables. /*operatorData*/
    ) external override view returns (bool) {
        return (_canTransfer(from, to, value, data));
    }

    function tokensToTransfer(
        bytes4, /*functionSig*/
        bytes32, /*partition*/
        address, /*operator*/
        address from,
        address to,
        uint256 value,
        bytes calldata data,
        bytes calldata // Comments to avoid compilation warnings for unused variables. /*operatorData*/
    ) external override {
        require(_canTransfer(from, to, value, data), "56"); // 0x56	invalid sender
    }

    function _canTransfer(
        address, /*from*/
        address, /*to*/
        uint256, /*value*/
        bytes memory data // Comments to avoid compilation warnings for unused variables.
    ) internal pure returns (bool) {
        bytes32 data32;
        assembly {
            data32 := mload(add(data, 32))
        }
        if (data32 == _TRANSFER_REVERT) {
            return false;
        } else {
            return true;
        }
    }
}
