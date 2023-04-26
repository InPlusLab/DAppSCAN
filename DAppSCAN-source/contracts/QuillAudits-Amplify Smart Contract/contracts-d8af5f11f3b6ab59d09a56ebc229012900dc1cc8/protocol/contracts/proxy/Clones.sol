// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

//solhint-disable max-line-length
//solhint-disable no-inline-assembly
/**
 * @dev https://eips.ethereum.org/EIPS/eip-1167[EIP 1167] is a standard for
 * deploying minimal proxy contracts, also known as "clones".
 *
 * > To simply and cheaply clone contract functionality in an immutable way, this standard specifies
 * > a minimal bytecode implementation that delegates all calls to a known, fixed address.
 *_
 */
library Clones {

  function createClone(address target) internal returns (address result) {
    bytes20 targetBytes = bytes20(target);

    assembly {
        let clone := mload(0x40)
        mstore(clone, 0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000)
        mstore(add(clone, 0x14), targetBytes)
        mstore(add(clone, 0x28), 0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000)
        result := create(0, clone, 0x37)
    }

    require(result != address(0), "ERC1167: create failed");
  }

  function isClone(address target, address query) internal view returns (bool result) {
    bytes20 targetBytes = bytes20(target);
    assembly {
        let clone := mload(0x40)
        mstore(clone, 0x363d3d373d3d3d363d7300000000000000000000000000000000000000000000)
        mstore(add(clone, 0xa), targetBytes)
        mstore(add(clone, 0x1e), 0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000)

        let other := add(clone, 0x40)
        extcodecopy(query, other, 0, 0x2d)
        result := and(
            eq(mload(clone), mload(other)),
            eq(mload(add(clone, 0xd)), mload(add(other, 0xd)))
        )
    }
  }
}