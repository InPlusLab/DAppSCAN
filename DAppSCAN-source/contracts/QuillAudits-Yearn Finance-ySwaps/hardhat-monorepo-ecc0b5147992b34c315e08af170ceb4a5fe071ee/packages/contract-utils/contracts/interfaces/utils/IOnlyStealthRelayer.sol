// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

interface IOnlyStealthRelayer {
  event StealthRelayerSet(address _stealthRelayer);

  function setStealthRelayer(address _stealthRelayer) external;
}
