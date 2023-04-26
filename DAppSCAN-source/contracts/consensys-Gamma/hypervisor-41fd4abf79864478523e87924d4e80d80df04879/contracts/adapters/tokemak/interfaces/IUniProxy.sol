pragma solidity =0.6.11;
pragma experimental ABIEncoderV2;

interface IUniProxy {

  function deposit(
    uint256 deposit0,
    uint256 deposit1,
    address to,
    address from,
    address pos
  ) external returns (uint256 shares);

}
