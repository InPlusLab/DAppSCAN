// SPDX-License-Identifier: MIT

pragma solidity ^0.7.0;

import './IVat.sol';
import './IGem.sol';

abstract contract IDaiJoin {
  function vat() public virtual returns (IVat);

  function dai() public virtual returns (IGem);

  function join(address, uint256) public payable virtual;

  function exit(address, uint256) public virtual;
}
