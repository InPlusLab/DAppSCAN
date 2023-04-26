pragma solidity ^0.5.2;

interface IDToken {
  function mint(address _dst, uint256 _pie) external;

  function redeem(address _src, uint256 _wad) external;

  function redeemUnderlying(address _src, uint256 _pie) external;

  function getBaseData()
    external
    returns (
      uint256,
      uint256,
      uint256,
      uint256,
      uint256
    );

  function getHandlerInfo()
    external
    view
    returns (
      address[] memory,
      uint256[] memory,
      uint256[] memory
    );
}
