// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "./MintVault.sol";

contract BTCMintVault is MintVault {

// TODO: 不同的dAsset 可以可能有不同的实现mint。
  function underlyingBurn(uint amount) internal virtual override {
    IDUSD(underlying).burnme(amount);
  }

}