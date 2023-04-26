/**
 * Submitted for verification at Etherscan.io on 2018-06-20
 * This mock is for testing
 * Modifications have been made regarding syntax to align with
 * current solidity version
*/

pragma solidity 0.5.16;

import "@openzeppelin/contracts/math/SafeMath.sol";


contract ItokenRecipient {
  function receiveApproval(address _from, uint256 _value, address _token, bytes memory _extraData) public;
}

contract Owned {
    address public owner;
    address public newOwner;

    constructor() public {
        owner = msg.sender;
    }

    modifier onlyOwner {
        assert(msg.sender == owner);
        _;
    }

    function transferOwnership(address _newOwner) public onlyOwner {
        require(_newOwner != owner);
        newOwner = _newOwner;
    }

    function acceptOwnership() public {
        require(msg.sender == newOwner);
        emit OwnerUpdate(owner, newOwner);
        owner = newOwner;
        newOwner = address(0);
    }

    event OwnerUpdate(address _prevOwner, address _newOwner);
}

contract IERC20Token {
  function totalSupply() public returns (uint256 totalSupply);
  function balanceOf(address _owner) public view returns (uint256 balance) {}
  function transfer(address _to, uint256 _value) public returns (bool success) {}
  function transferFrom(address _from, address _to, uint256 _value) public returns (bool success) {}
  function approve(address _spender, uint256 _value) public returns (bool success) {}
  function allowance(address _owner, address _spender) public returns (uint256 remaining) {}

  event Transfer(address indexed _from, address indexed _to, uint256 _value);
  event Approval(address indexed _owner, address indexed _spender, uint256 _value);
}

contract Token is IERC20Token, Owned {

  using SafeMath for uint256;

  /* Public variables of the token */
  string public standard;
  string public name;
  string public symbol;
  uint8 public decimals;

  address public crowdsaleContractAddress;

  /* Private variables of the token */
  uint256 supply = 0;
  mapping (address => uint256) balances;
  mapping (address => mapping (address => uint256)) allowances;

  /* Events */
  event Mint(address indexed _to, uint256 _value);

  // validates address is the crowdsale owner
  modifier onlyCrowdsaleOwner() {
      require(msg.sender == crowdsaleContractAddress);
      _;
  }

  constructor() public {}

  /* Returns total supply of issued tokens */
  function totalSupply() public returns (uint256) {
    return supply;
  }

  /* Returns balance of address */
  function balanceOf(address _owner) public view returns (uint256 balance) {
    return balances[_owner];
  }

  /* Transfers tokens from your address to other */
  function transfer(address _to, uint256 _value) public returns (bool success) {
    require(_to != address(0) && _to != address(this));
    balances[msg.sender] = balances[msg.sender].sub(_value); // Deduct senders balance
    balances[_to] = balances[_to].add(_value);               // Add recivers blaance
    emit Transfer(msg.sender, _to, _value);                       // Raise Transfer event
    return true;
  }

  /* Approve other address to spend tokens on your account */
  function approve(address _spender, uint256 _value) public returns (bool success) {
    allowances[msg.sender][_spender] = _value;        // Set allowance
    emit Approval(msg.sender, _spender, _value);           // Raise Approval event
    return true;
  }

  /* Approve and then communicate the approved contract in a single tx */
  function approveAndCall(address _spender, uint256 _value, bytes memory _extraData) public returns (bool success) {
    ItokenRecipient spender = ItokenRecipient(_spender);            // Cast spender to tokenRecipient contract
    approve(_spender, _value);                                      // Set approval to contract for _value
    spender.receiveApproval(msg.sender, _value, address(this), _extraData);  // Raise method on _spender contract
    return true;
  }

  /* A contract attempts to get the coins */
  function transferFrom(address _from, address _to, uint256 _value) public returns (bool success) {
    require(_to != address(0) && _to != address(this));
    balances[_from] = balances[_from].sub(_value);                              // Deduct senders balance
    balances[_to] = balances[_to].add(_value);                                  // Add recipient blaance
    allowances[_from][msg.sender] = allowances[_from][msg.sender].sub(_value);  // Deduct allowance for this address
    emit Transfer(_from, _to, _value);                                               // Raise Transfer event
    return true;
  }

  function allowance(address _owner, address _spender) public returns (uint256 remaining) {
    return allowances[_owner][_spender];
  }

  function mintTokens(address _to, uint256 _amount) public onlyCrowdsaleOwner {
    supply = supply.add(_amount);
    balances[_to] = balances[_to].add(_amount);
    emit Mint(_to, _amount);
    emit Transfer(msg.sender, _to, _amount);
  }

  function salvageTokensFromContract(address _tokenAddress, address _to, uint _amount) public onlyOwner {
    IERC20Token(_tokenAddress).transfer(_to, _amount);
  }
}

contract StormToken is Token {

	bool public transfersEnabled = false;    // true if transfer/transferFrom are enabled, false if not

	// triggered when the total supply is increased
	event Issuance(uint256 _amount);
	// triggered when the total supply is decreased
	event Destruction(uint256 _amount);


  /* Initializes contract */
  constructor(address _crowdsaleAddress) public {
    standard = "Storm Token v1.0";
    name = "Storm Token";
    symbol = "STORM"; // token symbol
    decimals = 18;
    crowdsaleContractAddress = _crowdsaleAddress;
  }

    // validates an address - currently only checks that it isn't null
    modifier validAddress(address _address) {
        require(_address != address(0));
        _;
    }

    // verifies that the address is different than this contract address
    modifier notThis(address _address) {
        require(_address != address(this));
        _;
    }

    // allows execution only when transfers aren't disabled
    modifier transfersAllowed {
        assert(transfersEnabled);
        _;
    }

   /**
        @dev disables/enables transfers
        can only be called by the contract owner

        @param _disable    true to disable transfers, false to enable them
    */
    function disableTransfers(bool _disable) public onlyOwner {
        transfersEnabled = !_disable;
    }

    /**
        @dev increases the token supply and sends the new tokens to an account
        can only be called by the contract owner

        @param _to         account to receive the new amount
        @param _amount     amount to increase the supply by
    */
    function issue(address _to, uint256 _amount)
        public
        onlyOwner
        validAddress(_to)
        notThis(_to)
    {
        supply = supply.add(_amount);
        balances[_to] = balances[_to].add(_amount);

        emit Issuance(_amount);
        emit Transfer(address(this), _to, _amount);
    }

    /**
        @dev removes tokens from an account and decreases the token supply
        can be called by the contract owner to destroy tokens from any account or by any holder to destroy tokens from his/her own account

        @param _from       account to remove the amount from
        @param _amount     amount to decrease the supply by
    */
    function destroy(address _from, uint256 _amount) public {
        require(msg.sender == _from || msg.sender == owner); // validate input

        balances[_from] = balances[_from].sub(_amount);
        supply = supply.sub(_amount);

        emit Transfer(_from, address(this), _amount);
        emit Destruction(_amount);
    }

    // ERC20 standard method overrides with some extra functionality

    /**
        @dev send coins
        throws on any error rather then return a false flag to minimize user errors
        in addition to the standard checks, the function throws if transfers are disabled

        @param _to      target address
        @param _value   transfer amount

        @return true if the transfer was successful, false if it wasn't
    */
    function transfer(address _to, uint256 _value) public transfersAllowed returns (bool success) {
        assert(super.transfer(_to, _value));
        return true;
    }
  
    function transfers(address[] memory _recipients, uint256[] memory _values) public transfersAllowed onlyOwner returns (bool success) {
        require(_recipients.length == _values.length); // Check if input data is correct

        for (uint cnt = 0; cnt < _recipients.length; cnt++) {
            assert(super.transfer(_recipients[cnt], _values[cnt]));
        }
        return true;
    }

    /**
        @dev an account/contract attempts to get the coins
        throws on any error rather then return a false flag to minimize user errors
        in addition to the standard checks, the function throws if transfers are disabled

        @param _from    source address
        @param _to      target address
        @param _value   transfer amount

        @return true if the transfer was successful, false if it wasn't
    */
    function transferFrom(address _from, address _to, uint256 _value) public transfersAllowed returns (bool success) {
        assert(super.transferFrom(_from, _to, _value));
        return true;
    }
}
