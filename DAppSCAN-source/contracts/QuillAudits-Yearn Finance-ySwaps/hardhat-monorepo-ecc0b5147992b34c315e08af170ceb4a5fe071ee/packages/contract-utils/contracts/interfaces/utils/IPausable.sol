// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

interface IPausable {
  event Paused(bool _paused);

  function pause(bool _paused) external;
}
