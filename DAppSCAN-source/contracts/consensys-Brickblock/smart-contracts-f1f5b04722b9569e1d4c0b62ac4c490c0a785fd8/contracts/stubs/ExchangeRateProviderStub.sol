pragma solidity 0.4.23;

import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "../interfaces/IRegistry.sol";
import "../interfaces/IExchangeRates.sol";


contract ExchangeRateProviderStub {
  IRegistry private registry;
  // used to check on if the contract has self destructed
  bool public isAlive = true;
  // used for testing simulated pending query
  bytes32 public pendingTestQueryId;
  // used for tetsing simulated testing recursion
  string public pendingQueryType;
  // used to check if should call again when testing recurision
  uint256 public shouldCallAgainIn;
  // used to check callback gas when testing recursion
  uint256 public shouldCallAgainWithGas;
  // used to check queryString when testing recursion
  string public shouldCallAgainWithQuery;
  // used to check simulated gas price setting
  uint256 public callbackGasPrice;

  // ensure that only the oracle or ExchangeRates contract are allowed
  modifier onlyAllowed()
  {
    require(
      msg.sender == registry.getContractAddress("ExchangeRates")
    );
    _;
  }

  modifier onlyExchangeRates()
  {
    require(msg.sender == registry.getContractAddress("ExchangeRates"));
    _;
  }

  constructor(
    address _registryAddress
  )
    public
  {
    require(_registryAddress != address(0));
    registry = IRegistry(_registryAddress);
  }

  // SIMULATE: set callbackGasPrice
  function setCallbackGasPrice(uint256 _gasPrice)
    onlyExchangeRates
    external
    returns (bool)
  {
    callbackGasPrice = _gasPrice;
    return true;
  }

  // SIMULATE: send query to oraclize, results sent to __callback
  // money can be forwarded on from ExchangeRates
  // leave out modifier as shown in
  function sendQuery(
    string _queryString,
    uint256 _callInterval, //not used in stub so will do a dummy check to get rid of compiler warnings
    uint256 _callbackGasLimit,
    string _queryType
  )
    onlyAllowed
    payable
    public
    returns (bool)
  {
    // simulate price of 2 000 000 000
    uint256 _simulatedPrice = 2e9;
    if (_simulatedPrice > address(this).balance) {
      // set to empty if not enough ether
      setQueryId(0x0, "");
      return false;
    } else {
      // simulate _queryId by hashing first element of bytes32 array
      pendingTestQueryId = keccak256(_queryString);
      setQueryId(pendingTestQueryId, _queryType);
      return true;
    }
  }

  // set queryIds on ExchangeRates for later validation when __callback happens
  function setQueryId(bytes32 _identifier, string _queryType)
    public
    returns (bool)
  {
    // get current address of ExchangeRates
    IExchangeRates _exchangeRates = IExchangeRates(
      registry.getContractAddress("ExchangeRates")
    );
    pendingTestQueryId = _identifier;
    // run setQueryId on ExchangeRates
    _exchangeRates.setQueryId(_identifier, _queryType);
  }

  // SIMULATE: callback function to get results of oraclize call
  // solium-disable-next-line mixedcase
  function simulate__callback(bytes32 _queryId, string _result)
    public
  {
    // make sure that the caller is oraclize
    IExchangeRates _exchangeRates = IExchangeRates(
      registry.getContractAddress("ExchangeRates")
    );

    bool _ratesActive = _exchangeRates.ratesActive();
    uint256 _callInterval;
    uint256 _callbackGasLimit;
    string memory _queryString;
    string memory _queryType = _exchangeRates.queryTypes(_queryId);
    (
      _callInterval,
      _callbackGasLimit,
      _queryString
    ) = _exchangeRates.getCurrencySettings(_queryType);

    // set rate on ExchangeRates contract
    _exchangeRates.setRate(_queryId, parseInt(_result));

    if (_callInterval > 0 && _ratesActive) {
      pendingTestQueryId = keccak256(_result);
      pendingQueryType = _queryType;
      shouldCallAgainWithQuery = _queryString;
      shouldCallAgainIn = _callInterval;
      shouldCallAgainWithGas = _callbackGasLimit;
    } else {
      delete pendingTestQueryId;
      delete pendingQueryType;
      shouldCallAgainWithQuery = "";
      shouldCallAgainIn = 0;
      shouldCallAgainWithGas = 0;
    }
  }

  // taken from oraclize in order to parseInts during testing
  // parseInt
  function parseInt(string _a)
    internal
    pure
    returns (uint)
  {
    return parseInt(_a, 0);
  }

  // parseInt(parseFloat*10^_b)
  function parseInt(string _a, uint _b)
    internal
    pure
    returns (uint)
  {
    bytes memory bresult = bytes(_a);
    uint mint = 0;
    bool decimals = false;
    for (uint i = 0; i < bresult.length; i++) {
      if ((bresult[i] >= 48) && (bresult[i] <= 57)) {
        if (decimals) {
          if (_b == 0)
            break;
          else
            _b--;
        }
        mint *= 10;
        mint += uint(bresult[i]) - 48;
      } else if (bresult[i] == 46)
        decimals = true;
    }
    if (_b > 0)
      mint *= 10 ** _b;
    return mint;
  }

  // used in case we need to get money out of the contract before replacing
  function selfDestruct(address _address)
    onlyExchangeRates
    public
  {
    selfdestruct(_address);
  }

  // ensure that we can fund queries by paying the contract
  function()
    payable
    public
  {}
}
