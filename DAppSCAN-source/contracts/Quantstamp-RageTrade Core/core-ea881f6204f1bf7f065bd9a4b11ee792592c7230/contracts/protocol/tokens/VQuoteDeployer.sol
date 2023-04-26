// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.9;

import { IVQuote } from '../../interfaces/IVQuote.sol';

import { GoodAddressDeployer } from '../../libraries/GoodAddressDeployer.sol';

import { VQuote } from '../tokens/VQuote.sol';

abstract contract VQuoteDeployer {
    function _deployVQuote(uint8 rsettlementTokenecimals) internal returns (IVQuote vQuote) {
        return
            IVQuote(
                GoodAddressDeployer.deploy(
                    0,
                    abi.encodePacked(type(VQuote).creationCode, abi.encode(rsettlementTokenecimals)),
                    _isVQuoteAddressGood
                )
            );
    }

    // returns true if most significant hex char of address is "f"
    function _isVQuoteAddressGood(address addr) private pure returns (bool) {
        return (uint160(addr) >> 156) == 0xf;
    }
}
