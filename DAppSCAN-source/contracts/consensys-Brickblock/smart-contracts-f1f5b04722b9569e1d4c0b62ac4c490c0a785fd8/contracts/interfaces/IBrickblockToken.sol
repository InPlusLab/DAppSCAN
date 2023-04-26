pragma solidity 0.4.23;

// limited BrickblockToken definition
interface IBrickblockToken {
  function transfer(
    address _to,
    uint256 _value
  )
    external
    returns (bool);

  function transferFrom(
    address from,
    address to,
    uint256 value
  )
    external
    returns (bool);

  function balanceOf(
    address _address
  )
    external
    view
    returns (uint256);
  
  function approve(
    address _spender,
    uint256 _value
  )
    external
    returns (bool);
}
