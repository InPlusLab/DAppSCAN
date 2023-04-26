//SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./Constants.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

// fee for protocol

contract FeeConf is Constants, Ownable {
  struct ReceiverRate {
    address receiver;
    uint16 rate;
  }

  mapping(bytes32 => ReceiverRate) configs;

  event SetConfig(bytes32 key,  address receiver, uint16 rate);

  constructor(address receiver) {
    setConfig("yield_fee", receiver, 2000); // 20%
    setConfig("borrow_fee", receiver, 50);  // 0.5%
    setConfig("repay_fee", receiver, 100);  // 1%
  // setConfig("liq_fee", receiver, 100);  // 0%
  }

  function setConfig(bytes32 _key, address _receiver, uint16 _rate) public onlyOwner {
    require(_receiver != address(0), "INVALID_RECEIVE");
    ReceiverRate storage conf = configs[_key];
    conf.receiver = _receiver;
    conf.rate = _rate;
    emit SetConfig(_key, _receiver, _rate);
  }

  function getConfig(bytes32 _key) external view returns (address, uint) {
    ReceiverRate memory conf = configs[_key];
    return (conf.receiver, conf.rate);
  }

}