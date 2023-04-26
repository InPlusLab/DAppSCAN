pragma solidity 0.4.23;

interface IAccessToken {
  function lockBBK(
    uint256 _value
  )
    external
    returns (bool);

  function unlockBBK(
    uint256 _value
  )
    external
    returns (bool);

  function transfer(
    address _to,
    uint256 _value
  )
    external
    returns (bool);

  function distribute(
    uint256 _amount
  )
    external
    returns (bool);

  function burn(
    address _address,
    uint256 _value
  )
    external
    returns (bool);
}