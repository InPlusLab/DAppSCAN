// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

interface ProxyFactoryInterface {
  function build(
    address _impl,
    address proxyAdmin,
    bytes calldata _data
  ) external returns (address);
}
