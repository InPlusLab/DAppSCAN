// SPDX-License-Identifier: MIT

pragma solidity ^0.7.0;

abstract contract IGetCdps {
  function getCdpsAsc(address manager, address guy)
    external
    view
    virtual
    returns (
      uint256[] memory ids,
      address[] memory urns,
      bytes32[] memory ilks
    );

  function getCdpsDesc(address manager, address guy)
    external
    view
    virtual
    returns (
      uint256[] memory ids,
      address[] memory urns,
      bytes32[] memory ilks
    );
}
