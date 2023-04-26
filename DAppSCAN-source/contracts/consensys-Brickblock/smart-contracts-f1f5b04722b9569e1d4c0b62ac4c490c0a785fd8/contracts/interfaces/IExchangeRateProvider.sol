pragma solidity 0.4.23;

interface IExchangeRateProvider {
  function sendQuery(
    string _queryString,
    uint256 _callInterval,
    uint256 _callbackGasLimit,
    string _queryType
  )
    external
    payable
    returns (bool);

  function setCallbackGasPrice(uint256 _gasPrice)
    external
    returns (bool);

  function selfDestruct(address _address)
    external;
}
