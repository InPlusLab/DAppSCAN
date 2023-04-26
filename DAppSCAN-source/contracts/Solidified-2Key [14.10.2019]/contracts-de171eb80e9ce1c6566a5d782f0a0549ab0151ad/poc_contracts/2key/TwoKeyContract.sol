pragma solidity ^0.4.24; //We have to specify what version of compiler this code will use

import "../../contracts/openzeppelin-solidity/contracts/token/ERC20/BasicToken.sol";
import '../../contracts/openzeppelin-solidity/contracts/ownership/Ownable.sol';
import "../../contracts/openzeppelin-solidity/contracts/token/ERC20/StandardToken.sol";
import './TwoKeyEventSource.sol';
import './TwoKeyReg.sol';
import '../../contracts/2key/libraries/Call.sol';

/**
 * @title Standard ERC20 token
 *
 * @dev Implementation of the basic standard token.
 * @dev https://github.com/ethereum/EIPs/issues/20
 * @dev Based on code by FirstBlood: https://github.com/Firstbloodio/token/blob/master/smart_contract/FirstBloodToken.sol
 */
contract TwoKeyContract is StandardToken, Ownable {
  event Fulfilled(address indexed to, uint256 units);
  event Rewarded(address indexed to, uint256 amount);
  event Log1(string s, uint256 units);
  event Log1A(string s, address a);


  using SafeMath for uint256;
  // Public variables of the token
  TwoKeyReg registry;
  TwoKeyEventSource eventSource;

  // address public owner;  // Who created the contract (business) // contained in Ownable.sol
  address owner_plasma; // must be set in constructor
  string public name;
  string public ipfs_hash;
  string public symbol;
  uint8 public decimals = 0;  // ARCs are not divisable
  uint256 public cost; // Cost of product in wei
  uint256 public bounty; // Cost of product in wei
  uint256 public quota;  // maximal tokens that can be passed in transferFrom
  uint256 unit_decimals;  // units being sold can be fractional (for example tokens in ERC20)

  // Private variables of the token
  // in all mappings the address is always a plasma address
  mapping (address => address) public received_from;
  mapping(address => uint256) public xbalances; // balance of external currency (ETH or 2Key coin)
  mapping(address => uint256) public units; // number of units bought

  // The cut from the bounty each influencer is taking + 1
  // zero (also the default value) indicates default behaviour in which the influencer takes an equal amount as other influencers
  mapping(address => uint256) internal influencer2cut;

  // All user information is stored on their plasma address
  // a msg sender must have a plasma address in registry
  function senderPlasma() public view returns (address) {
    address me = msg.sender;
    if (registry == address(0)) {
      return me;
    }
    address plasma = registry.ethereum2plasma(me);
    require(plasma != address(0),'your plasma address was not found in registry');

    return plasma;
  }

  function plasmaOf(address me) public view returns (address) {
    address plasma = me;
    if (registry == address(0)) {
      return plasma;
    }
    plasma = registry.ethereum2plasma(plasma);
    if (plasma != address(0)) {
      return plasma;
    }
    return me;  // assume me is a plasma address. TODO not to make this assumption
  }

  function ethereumOf(address me) public view returns (address) {
    // used in TwoKeyWeightedVoteContract to move coins
    address ethereum = me;
    if (registry == address(0)) {
      return ethereum;
    }
    ethereum = registry.plasma2ethereum(ethereum);
    if (ethereum != address(0)) {
      return ethereum;
    }
    return me; // assume me is a ethereum address. TODO not to make this assumption
  }

  function setCutOf(address me, uint256 cut) internal {
    // what is the percentage of the bounty s/he will receive when acting as an influencer
    // the value 255 is used to signal equal partition with other influencers
    // A sender can set the value only once in a contract
    address plasma = plasmaOf(me);
    require(influencer2cut[plasma] == 0 || influencer2cut[plasma] == cut, 'cut already set differently');
    influencer2cut[plasma] = cut;
  }

  function setCut(uint256 cut) public {
    setCutOf(msg.sender, cut);
  }

  function cutOf(address me) public view returns (uint256) {
    return influencer2cut[plasmaOf(me)];
  }

  function getCuts(address last_influencer) public view returns (uint256[]) {
    address[] memory influencers = getInfluencers(last_influencer);
    uint n_influencers = influencers.length;
    uint256[] memory cuts = new uint256[](n_influencers + 1);
    for (uint i = 0; i < n_influencers; i++) {
      address influencer = influencers[i];
      cuts[i] = cutOf(influencer);
    }
    cuts[n_influencers] = cutOf(last_influencer);
    return cuts;
  }

  /**
   * @dev Transfer tokens from one address to another
   * @param _from address The address which you want to send tokens from ALREADY converted to plasma
   * @param _to address The address which you want to transfer to ALREADY converted to plasma
   * @param _value uint256 the amount of tokens to be transferred
   */
  function transferFrom(address _from, address _to, uint256 _value) public onlyOwner returns (bool) {
    return transferFromInternal(_from, _to, _value);
  }
  function transferFromInternal(address _from, address _to, uint256 _value) internal returns (bool) {
    // _from and _to are assumed to be already converted to plasma address (e.g. using plasmaOf)
    require(_value == 1, 'can only transfer 1 ARC');
    require(_from != address(0), '_from undefined');
    require(_to != address(0), '_to undefined');
    _from = plasmaOf(_from);
    _to = plasmaOf(_to);

//    // normalize address to be plasma
//    _from = plasmaOf(_from);
//    _to = plasmaOf(_to);

    require(balances[_from] > 0,'_from does not have arcs');
    balances[_from] = balances[_from].sub(1);
    balances[_to] = balances[_to].add(quota);
    totalSupply_ = totalSupply_.add(quota.sub(1));

    emit Transfer(_from, _to, 1);
    if (received_from[_to] == 0) {
      // inform the 2key admin contract, once, that an influencer has joined
      if (eventSource != address(0)) {
        eventSource.joined(this, _from, _to);
      }
    }
    received_from[_to] = _from;
    return true;
  }

  /**
  * @dev transfer token for a specified address
  * @param _to The address to transfer to.
  * @param _value The amount to be transferred.
  */
  function transfer(address _to, uint256 _value) public returns (bool) {
    revert('transfer not implemented');
    return false;
  }

  function getConstantInfo() public view returns (string,string,uint256,uint256,uint256,address,string,uint256) {
    return (name,symbol,cost,bounty,quota,owner,ipfs_hash,unit_decimals);
  }

  function total_units() public view returns (uint256);

  /**
  * Gets the balance of the specified address.
  * me - The address to query the the balance of.
  * returns An uint256 representing the amount owned by the passed address.
  */
  function balanceOf(address me) public view returns (uint256) {
    return balances[plasmaOf(me)];
  }

  function xbalanceOf(address me) public view returns (uint256) {
    return xbalances[plasmaOf(me)];
  }

  function unitsOf(address me) public view returns (uint256) {
    return units[plasmaOf(me)];
  }

  function getDynamicInfo(address me) public view returns (uint256,uint256,uint256,uint256,uint256,uint256,uint256) {
    // address(this).balance is solidity reserved word for the the ETH amount deposited in the contract
    return (balanceOf(me),unitsOf(me),xbalanceOf(me),totalSupply_,address(this).balance,total_units(),cutOf(me));
  }

   function () external payable {
     buyProduct();
   }

  // buy product. if you dont have ARCs then first take them (join) from _from
  function buyFrom(address _from) public payable {
    _from = plasmaOf(_from);
    address _to = senderPlasma();
    if (balanceOf(_to) == 0) {
      transferFromInternal(_from, _to, 1);
    }
    buyProduct();
  }

  function redeem() public {
    address influencer = senderPlasma();
    uint256 b = xbalances[influencer];


    uint256 bmax = address(this).balance;
    if (b > bmax) {
      b = bmax;
    }
    if (b == 0) {
      return;
    }

    xbalances[influencer] = xbalances[influencer].sub(b);
    // super important to send to msg.senbder not to influencer
    if(!msg.sender.send(b)) {
       revert("failed to send");
    }
  }

  // low level product purchase function
  function buyProduct() public payable;

  function getInfluencers(address customer) public view returns (address[]) {
    // build a list of all influencers (using plasma adress) from converter back to to contractor
    // dont count the conveter and contractr themselves
    address influencer = plasmaOf(customer);
    // first count how many influencers
    uint n_influencers = 0;
    while (true) {
      influencer = plasmaOf(received_from[influencer]);  // already a plasma address
      require(influencer != address(0),'not connected to contractor');
      if (influencer == owner_plasma) {
        break;
      }
      n_influencers++;
    }
    // allocate temporary memory to hold the influencers
    address[] memory influencers = new address[](n_influencers);
    // fill the array of influencers in reverse order, from the last influencer just before the converter to the
    // first influencer just after the contractor
    influencer = plasmaOf(customer);
    while (n_influencers > 0) {
      influencer = plasmaOf(received_from[influencer]);
      n_influencers--;
      influencers[n_influencers] = influencer;
    }

    return influencers;
  }

  function buyProductInternal(uint256 _units, uint256 _bounty) public payable {
    // buy coins with cut
    // low level product purchase function
    address customer = senderPlasma();
    require(balanceOf(customer) > 0,"no arcs");

    uint256 _total_units = total_units();
//    emit Log1('_total_units',_total_units);

    require(_units > 0,"no units requested");
    require(_total_units >= _units,"not enough units available in stock");
    address[] memory influencers = getInfluencers(customer);
    uint n_influencers = influencers.length;

    // distribute bounty to influencers
    uint256 total_bounty = 0;
    for (uint i = 0; i < n_influencers; i++) {
      address influencer = plasmaOf(influencers[i]);  // influencers is in reverse order
      uint256 b;
      if (i == n_influencers-1) {  // if its the last influencer then all the bounty goes to it.
        b = _bounty;
      } else {
        uint256 cut = cutOf(influencer);
        if (cut > 0 && cut <= 101) {
          b = _bounty.mul(cut.sub(1)).div(100);
        } else {  // cut == 0 or 255 indicates equal particine of the bounty
          b = _bounty.div(n_influencers-i);
        }
      }
      xbalances[influencer] = xbalances[influencer].add(b);
      emit Rewarded(influencer, b);
      total_bounty = total_bounty.add(b);
      _bounty = _bounty.sub(b);
    }

    // all that is left from the cost is given to the owner for selling the product
    xbalances[owner_plasma] = xbalances[owner_plasma].add(msg.value).sub(total_bounty); // TODO we want the cost of a token to be fixed?
    units[customer] = units[customer].add(_units);

    emit Fulfilled(customer, units[customer]);
  }
}

contract TwoKeyAcquisitionContract is TwoKeyContract
{
  uint256 public _total_units; // total number of units on offer

  // Initialize all the constants
  constructor(TwoKeyReg _reg, TwoKeyEventSource _eventSource, string _name, string _symbol,
        uint256 _tSupply, uint256 _quota, uint256 _cost, uint256 _bounty,
        uint256 _units, string _ipfs_hash) public {
    require(_bounty <= _cost,"bounty bigger than cost");
    // owner = msg.sender;  // done in Ownable()
    // We do an explicit type conversion from `address`
    // to `TwoKeyReg` and assume that the type of
    // the calling contract is TwoKeyReg, there is
    // no real way to check that.
    name = _name;
    symbol = _symbol;
    totalSupply_ = _tSupply;
    cost = _cost;
    bounty = _bounty;
    quota = _quota;
    _total_units = _units;
    ipfs_hash = _ipfs_hash;
    unit_decimals = 0;  // dont allow fractional units


    registry = _reg;
    owner_plasma = plasmaOf(owner); // can be called after setting registry
    received_from[owner_plasma] = owner_plasma;  // allow owner to buy from himself
    balances[owner_plasma] = _tSupply;

    if (_eventSource != address(0)) {
      eventSource = _eventSource;
      eventSource.created(this, owner);
    }
  }

  function total_units() public view returns (uint256) {
    return _total_units;
  }

  // low level product purchase function
  function buyProduct() public payable {
    // caluclate the number of units being purchased
    uint _units = msg.value.div(cost);
    require(msg.value == cost * _units, "ethere sent does not divide equally into units");
    // bounty is the cost of a single token. Compute the bounty for the units
    // we are buying
    uint256 _bounty = bounty.mul(_units);

    buyProductInternal(_units, _bounty);

    _total_units = _total_units.sub(_units);
  }
}

contract TwoKeyPresellContract is TwoKeyContract {
  StandardToken public erc20_token_sell_contract;

//  address dc;

  // Initialize all the constants
  constructor(TwoKeyReg _reg, TwoKeyEventSource _eventSource, string _name, string _symbol,
        uint256 _tSupply, uint256 _quota, uint256 _cost, uint256 _bounty,
        string _ipfs_hash, StandardToken _erc20_token_sell_contract) public {
    require(_bounty <= _cost,"bounty bigger than cost");
    // owner = msg.sender;  // done in Ownable()
    // We do an explicit type conversion from `address`
    // to `TwoKeyReg` and assume that the type of
    // the calling contract is TwoKeyReg, there is
    // no real way to check that.
    name = _name;
    symbol = _symbol;
    totalSupply_ = _tSupply;
    cost = _cost;
    bounty = _bounty;
    quota = _quota;
    ipfs_hash = _ipfs_hash;
    registry = _reg;
    owner_plasma = plasmaOf(owner); // can be called after setting registry
    received_from[owner_plasma] = owner_plasma;  // allow owner to buy from himself
    balances[owner_plasma] = _tSupply;
    if (_eventSource != address(0)) {
      eventSource = _eventSource;
      eventSource.created(this, owner);
    }

    if (_erc20_token_sell_contract != address(0)) {
      // fractional units are determined by the erc20 contract
      erc20_token_sell_contract = _erc20_token_sell_contract;
      unit_decimals = Call.params0(erc20_token_sell_contract, "decimals()");
//      emit Log1('start_unit_decimals', unit_decimals); // does not work in constructor on geth
      require(unit_decimals >= 0,"unit decimals to low");
      require(unit_decimals <= 18,"unit decimals to big");
    }
  }

  function total_units() public view returns (uint256) {
    uint256 _total_units;
//    _total_units = erc20_token_sell_contract.balanceOf(address(this));
    _total_units = Call.params1(erc20_token_sell_contract, "balanceOf(address)",uint(this));
    return _total_units;
  }

  // low level product purchase function

  function buyProduct() public payable {
//    emit Log1('unit_decimals', unit_decimals);
//    unit_decimals = 18; // uint256(erc20_token_sell_contract.decimals());
    // cost is the cost of a single token. Each token has 10**decimals units
    uint256 _units = msg.value.mul(10**unit_decimals).div(cost);
//    emit Log1('units', _units);
    // bounty is the cost of a single token. Compute the bounty for the units
    // we are buying
    uint256 _bounty = bounty.mul(_units).div(10**unit_decimals);
//    emit Log1('_bounty', _bounty);

    buyProductInternal(_units, _bounty);

//    emit Log1('going to transfer', _units);
//    emit Log1A('coin', address(erc20_token_sell_contract));

    // We are sending the bought coins to the ether address of the converter
    // keep this last
    require(address(erc20_token_sell_contract).call(bytes4(keccak256("transfer(address,uint256)")),msg.sender,_units),
      "failed to send coins");
  }
}
