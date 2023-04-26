pragma solidity 0.4.23;

import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "./interfaces/IRegistry.sol";
import "./interfaces/IExchangeRateProvider.sol";



/*
Q/A
Q: Why are there two contracts for ExchangeRates?
A: Testing Oraclize seems to be a bit difficult especially considering the
bridge requires node v6... With that in mind, it was decided that the best way
to move forward was to isolate the oraclize functionality and replace with
a stub in order to facilitate effective tests.

Q: Why are rates private?
A: So that they can be returned through custom getters getRate and
getRateReadable. This is so that we can revert when a rate has not been
initialized or an error happened when fetching. Oraclize returns '' when
erroring which we parse as a uint256 which turns to 0.
*/

// main contract
contract ExchangeRates is Ownable {
  uint8 public constant version = 1;
  // instance of Registry to be used for getting other contract addresses
  IRegistry private registry;
  // flag used to tell recursive rate fetching to stop
  bool public ratesActive = true;

  struct Settings {
    string queryString;
    uint256 callInterval;
    uint256 callbackGasLimit;
  }

  // the actual exchange rate for each currency
  // private so that when rate is 0 (error or unset) we can revert through
  // getter functions getRate and getRateReadable
  mapping (bytes32 => uint256) private rates;
  // points to currencySettings from callback
  // is used to validate queryIds from ExchangeRateProvider
  mapping (bytes32 => string) public queryTypes;
  // storage for query settings... modifiable for each currency
  // accessed and used by ExchangeRateProvider
  mapping (string => Settings) private currencySettings;

  event RateUpdatedEvent(string currency, uint256 rate);
  event QueryNoMinBalanceEvent();
  event QuerySentEvent(string currency);
  event SettingsUpdatedEvent(string currency);

  // used to only allow specific contract to call specific functions
  modifier onlyContract(string _contractName)
  {
    require(
      msg.sender == registry.getContractAddress(_contractName)
    );
    _;
  }

  // sets registry for talking to ExchangeRateProvider
  constructor(
    address _registryAddress
  )
    public
    payable
  {
    require(_registryAddress != address(0));
    registry = IRegistry(_registryAddress);
    owner = msg.sender;
  }

  // start rate fetching for a specific currency. Kicks off the first of
  // possibly many recursive query calls on ExchangeRateProvider to get rates.
  function fetchRate(string _queryType)
    external
    onlyOwner
    payable
    returns (bool)
  {
    // get the ExchangeRateProvider from registry
    IExchangeRateProvider provider = IExchangeRateProvider(
      registry.getContractAddress("ExchangeRateProvider")
    );

    // get settings to use in query on ExchangeRateProvider
    uint256 _callInterval;
    uint256 _callbackGasLimit;
    string memory _queryString;
    (
      _callInterval,
      _callbackGasLimit,
      _queryString
    ) = getCurrencySettings(_queryType);
    // check that queryString isn't empty before making the query
    require(
      bytes(_queryString).length > 0,
      "_queryString is empty"
    );
    // make query on ExchangeRateProvider
    // forward any ether value sent on to ExchangeRateProvider
    // setQuery is called from ExchangeRateProvider to trigger an event
    // whether there is enough balance or not
    provider.sendQuery.value(msg.value)(
      _queryString,
      _callInterval,
      _callbackGasLimit,
      _queryType
    );
    return true;
  }

  //
  // start exchange rate provider only functions
  //

  // set a pending queryId callable only by ExchangeRateProvider
  // set from sendQuery on ExchangeRateProvider
  // used to check that correct query is being matched to correct values
  function setQueryId(
    bytes32 _queryId,
    string _queryType
  )
    external
    onlyContract("ExchangeRateProvider")
    returns (bool)
  {
    if (_queryId[0] != 0x0 && bytes(_queryType)[0] != 0x0) {
      emit QuerySentEvent(_queryType);
      queryTypes[_queryId] = _queryType;
    } else {
      emit QueryNoMinBalanceEvent();
    }
    return true;
  }

  // called only by ExchangeRateProvider
  // sets the rate for a given currency when query __callback occurs.
  // checks that the queryId returned is correct.
  function setRate(
    bytes32 _queryId,
    uint256 _result
  )
    external
    onlyContract("ExchangeRateProvider")
    returns (bool)
  {
    // get the query type (usd, eur, etc)
    string memory _queryType = queryTypes[_queryId];
    // check that first byte of _queryType is not 0 (something wrong or empty)
    // if the queryType is 0 then the queryId is incorrect
    require(bytes(_queryType).length > 0);
    // set _queryId to empty (uninitialized, to prevent from being called again)
    delete queryTypes[_queryId];
    // set currency rate depending on _queryType (USD, EUR, etc.)
    rates[keccak256(_queryType)] = _result;
    // event for particular rate that was updated
    emit RateUpdatedEvent(
      _queryType,
      _result
    );

    return true;
  }
  
  //
  // end exchange rate provider only settings
  //

  /*
  set setting for a given currency:
  currencyName: used as identifier to store settings (stored as bytes8)
  queryString: the http endpoint to hit to get data along with format
    example: "json(https://min-api.cryptocompare.com/data/price?fsym=ETH&tsyms=USD).USD"
  callInterval: used to specifiy how often (if at all) the rate should refresh
  callbackGasLimit: used to specify how much gas to give the oraclize callback
  */
  function setCurrencySettings(
    string _currencyName,
    string _queryString,
    uint256 _callInterval,
    uint256 _callbackGasLimit
  )
    external
    onlyOwner
    returns (bool)
  {
    // store settings by bytes8 of string, convert queryString to bytes array
    currencySettings[toUpperCase(_currencyName)] = Settings(
      _queryString,
      _callInterval,
      _callbackGasLimit
    );
    emit SettingsUpdatedEvent(_currencyName);
    return true;
  }

  // set only query string in settings for a given currency
  function setCurrencySettingQueryString(
    string _currencyName,
    string _queryString
  )
    external
    onlyOwner
    returns (bool)
  {
    Settings storage _settings = currencySettings[toUpperCase(_currencyName)];
    _settings.queryString = _queryString;
    emit SettingsUpdatedEvent(_currencyName);
    return true;
  }

  // set only callInterval in settings for a given currency
  function setCurrencySettingCallInterval(
    string _currencyName,
    uint256 _callInterval
  )
    external
    onlyOwner
    returns (bool)
  {
    Settings storage _settings = currencySettings[toUpperCase(_currencyName)];
    _settings.callInterval = _callInterval;
    emit SettingsUpdatedEvent(_currencyName);
    return true;
  }

  // set only callbackGasLimit in settings for a given currency
  function setCurrencySettingCallbackGasLimit(
    string _currencyName,
    uint256 _callbackGasLimit
  )
    external
    onlyOwner
    returns (bool)
  {
    Settings storage _settings = currencySettings[toUpperCase(_currencyName)];
    _settings.callbackGasLimit = _callbackGasLimit;
    emit SettingsUpdatedEvent(_currencyName);
    return true;
  }

  // set callback gasPrice for all currencies
  function setCallbackGasPrice(uint256 _gasPrice)
    external
    onlyOwner
    returns (bool)
  {
    // get the ExchangeRateProvider from registry
    IExchangeRateProvider provider = IExchangeRateProvider(
      registry.getContractAddress("ExchangeRateProvider")
    );
    provider.setCallbackGasPrice(_gasPrice);
    emit SettingsUpdatedEvent("ALL");
    return true;
  }

  // set to active or inactive in order to stop recursive rate fetching
  // rate needs to be fetched once in order for it to stop.
  function toggleRatesActive()
    external
    onlyOwner
    returns (bool)
  {
    ratesActive = !ratesActive;
    emit SettingsUpdatedEvent("ALL");
    return true;
  }

  //
  // end setter functions
  //

  //
  // start getter functions
  //

  // retrieve settings for a given currency (queryType)
  function getCurrencySettings(string _queryTypeString)
    public
    view
    returns (uint256, uint256, string)
  {
    Settings memory _settings = currencySettings[_queryTypeString];
    return (
      _settings.callInterval,
      _settings.callbackGasLimit,
      _settings.queryString
    );
  }

  // get rate with string for easy use by regular accounts
  function getRate(string _queryTypeString)
    external
    view
    returns (uint256)
  {
    uint256 _rate = rates[keccak256(toUpperCase(_queryTypeString))];
    require(_rate > 0, "Fiat rate should be higher than zero");
    return _rate;
  }

  // get rate with bytes32 for easier assembly calls
  // uppercase protection not provided...
  function getRate32(bytes32 _queryType32)
    external
    view
    returns (uint256)
  {
    uint256 _rate = rates[_queryType32];
    require(_rate > 0, "Fiat rate should be higher than zero");
    return _rate;
  }

  //
  // end getter functions
  //

  // 
  // start utility functions
  //

  // convert string to uppercase to ensure that there are not multiple
  // instances of same currencies
  function toUpperCase(string _base)
    pure
    public
    returns (string)
  {
    bytes memory _stringBytes = bytes(_base);
    for (
      uint _byteCounter = 0;
      _byteCounter < _stringBytes.length;
      _byteCounter++
    ) {
      if (
        _stringBytes[_byteCounter] >= 0x61 &&
        _stringBytes[_byteCounter] <= 0x7A
      ) {
        _stringBytes[_byteCounter] = bytes1(
          uint8(_stringBytes[_byteCounter]) - 32
        );
      }
    }
    return string(_stringBytes);
  }

  //
  // end utility functions
  //

  // used for selfdestructing the provider in order to get back any unused ether
  // useful for upgrades where we want to get money back from contract
  function killProvider(address _address)
    public
    onlyOwner
  {
    // get the ExchangeRateProvider from registry
    IExchangeRateProvider provider = IExchangeRateProvider(
      registry.getContractAddress("ExchangeRateProvider")
    );
    provider.selfDestruct(_address);
  }

  // prevent anyone from sending funds other than selfdestructs of course :)
  function()
    public
    payable
  {
    revert();
  }
}
