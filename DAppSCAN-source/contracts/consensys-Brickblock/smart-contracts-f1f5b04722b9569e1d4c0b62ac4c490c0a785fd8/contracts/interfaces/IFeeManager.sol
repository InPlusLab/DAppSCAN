pragma solidity 0.4.23;

interface IFeeManager {
  function claimFee(
    uint256 _value
  )
    external
    returns (bool);

  function payFee()
    external
    payable
    returns (bool);
}

