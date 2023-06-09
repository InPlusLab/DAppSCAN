// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.4;

import "../libraries/Asset.sol";

contract Counter {
  bool public shouldRevert;
  uint256 public count = 0;

  constructor() {
    shouldRevert = false;
  }

  function setShouldRevert(bool value) public {
    shouldRevert = value;
  }

  function increment() public {
    require(!shouldRevert, "increment: shouldRevert is true");
    count += 1;
  }

  function incrementAndSend(address assetId, address recipient, uint256 amount) public payable {
    if (Asset.isNativeAsset(assetId)) {
      require(msg.value == amount, "incrementAndSend: INVALID_ETH_AMOUNT");
    } else {
      require(msg.value == 0, "incrementAndSend: ETH_WITH_ERC");
      Asset.transferFromERC20(assetId, msg.sender, address(this), amount);
    }
    increment();

    Asset.transferAsset(assetId, payable(recipient), amount);
  }
}