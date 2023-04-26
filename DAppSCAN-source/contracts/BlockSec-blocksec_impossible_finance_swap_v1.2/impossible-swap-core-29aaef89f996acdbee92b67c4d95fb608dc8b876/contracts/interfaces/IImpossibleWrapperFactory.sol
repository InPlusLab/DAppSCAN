// SPDX-License-Identifier: GPL-3
pragma solidity =0.7.6;

interface IImpossibleWrapperFactory {
    event WrapCreated(address, address, uint256, uint256);
    event WrapDeleted(address, address);

    function tokensToWrappedTokens(address) external view returns (address);

    function wrappedTokensToTokens(address) external view returns (address);
}
