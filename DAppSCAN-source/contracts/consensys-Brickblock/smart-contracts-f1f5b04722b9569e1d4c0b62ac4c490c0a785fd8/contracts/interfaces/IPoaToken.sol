pragma solidity 0.4.23;

interface IPoaToken {
  function setupContract
  (
    string _name,
    string _symbol,
    // fiat symbol used in ExchangeRates
    string _fiatCurrency,
    address _broker,
    address _custodian,
    uint256 _totalSupply,
    // given as unix time (seconds since 01.01.1970)
    uint256 _startTime,
    // given as seconds
    uint256 _fundingTimeout,
    uint256 _activationTimeout,
    // given as fiat cents
    uint256 _fundingGoalInCents
  )
    external
    returns (bool);

  function pause()
    external;
  
  function unpause()
    external;
  
  function terminate()
    external
    returns (bool);
  
  function proofOfCustody()
    external
    view
    returns (string);
  
  function toggleWhitelistTransfers()
    external
    returns (bool);
}