pragma solidity 0.4.23;

interface IPoaManager {
  function getTokenStatus(
    address _tokenAddress
  )
    external
    view
    returns (bool);
}
