pragma solidity 0.4.18;

import "frozen-zeppelin-solidity/contracts/token/PausableToken.sol";


contract BrickblockToken is PausableToken {

  string public constant name = "BrickblockToken";
  string public constant symbol = "BBK";
  uint256 public constant initialSupply = 500 * (10 ** 6) * (10 ** uint256(decimals));
  uint256 public companyTokens;
  uint256 public bonusTokens;
  uint8 public constant contributorsShare = 51;
  uint8 public constant companyShare = 35;
  uint8 public constant bonusShare = 14;
  uint8 public constant decimals = 18;
  address public bonusDistributionAddress;
  address public fountainContractAddress;
  bool public tokenSaleActive;
  bool public dead = false;

  event TokenSaleFinished
  (
    uint256 totalSupply,
    uint256 distributedTokens,
    uint256 bonusTokens,
    uint256 companyTokens
  );
  event Burn(address indexed burner, uint256 value);

  // This modifier is used in `distributeTokens()` and ensures that no more than 51% of the total supply can be distributed
  modifier supplyAvailable(uint256 _value) {
    uint256 _distributedTokens = initialSupply.sub(balances[this].add(bonusTokens));
    uint256 _maxDistributedAmount = initialSupply.mul(contributorsShare).div(100);
    require(_distributedTokens.add(_value) <= _maxDistributedAmount);
    _;
  }

  function BrickblockToken(address _bonusDistributionAddress)
    public
  {
    require(_bonusDistributionAddress != address(0));
    bonusTokens = initialSupply.mul(bonusShare).div(100);
    companyTokens = initialSupply.mul(companyShare).div(100);
    bonusDistributionAddress = _bonusDistributionAddress;
    totalSupply = initialSupply;
    balances[this] = initialSupply;
    Transfer(address(0), this, initialSupply);
    // distribute bonusTokens to bonusDistributionAddress
    balances[this] = balances[this].sub(bonusTokens);
    balances[bonusDistributionAddress] = balances[bonusDistributionAddress].add(bonusTokens);
    Transfer(this, bonusDistributionAddress, bonusTokens);
    // we need to start with trading paused to make sure that there can be no transfers while the token sale is still ongoing
    // we will unpause the contract manually after finalizing the token sale by calling `unpause()` which is a function inherited from PausableToken
    paused = true;
    tokenSaleActive = true;
  }

  // For worst case scenarios, e.g. when a vulnerability in this contract would be discovered and we would have to deploy a new contract
  // This is only for visibility purposes to publicly indicate that we consider this contract "dead" and don't intend to re-activate it ever again
  function toggleDead()
    external
    onlyOwner
    returns (bool)
  {
    dead = !dead;
  }

  // Helper function used in changeFountainContractAddress to ensure an address parameter is a contract and not an external address
  function isContract(address addr)
    private
    view
    returns (bool)
  {
    uint _size;
    assembly { _size := extcodesize(addr) }
    return _size > 0;
  }

  // Fountain contract address could change over time, so we need the ability to update its address
  function changeFountainContractAddress(address _newAddress)
    external
    onlyOwner
    returns (bool)
  {
    require(isContract(_newAddress));
    require(_newAddress != address(this));
    require(_newAddress != owner);
    fountainContractAddress = _newAddress;
    return true;
  }

  // Custom transfer function that enables us to distribute tokens while contract is paused. Cannot be used after end of token sale
  function distributeTokens(address _contributor, uint256 _value)
    external
    onlyOwner
    supplyAvailable(_value)
    returns (bool)
  {
    require(tokenSaleActive == true);
    require(_contributor != address(0));
    require(_contributor != owner);
    balances[this] = balances[this].sub(_value);
    balances[_contributor] = balances[_contributor].add(_value);
    Transfer(this, _contributor, _value);
    return true;
  }

  // Distribute tokens reserved for partners and staff to a wallet owned by Brickblock
  function distributeBonusTokens(address _recipient, uint256 _value)
    external
    onlyOwner
    returns (bool)
  {
    require(_recipient != address(0));
    require(_recipient != owner);
    balances[bonusDistributionAddress] = balances[bonusDistributionAddress].sub(_value);
    balances[_recipient] = balances[_recipient].add(_value);
    Transfer(bonusDistributionAddress, _recipient, _value);
    return true;
  }

  // Calculate the shares for company, bonus & contibutors based on the intial totalSupply of 500.000.000 tokens - not what is left over after burning
  function finalizeTokenSale()
    external
    onlyOwner
    returns (bool)
  {
    // ensure that sale is active. is set to false at the end. can only be performed once.
    require(tokenSaleActive == true);
    // ensure that fountainContractAddress has been set
    require(fountainContractAddress != address(0));
    // calculate new total supply. need to do this in two steps in order to have accurate totalSupply due to integer division
    uint256 _distributedTokens = initialSupply.sub(balances[this].add(bonusTokens));
    uint256 _newTotalSupply = _distributedTokens.add(bonusTokens.add(companyTokens));
    // unpurchased amount of tokens which will be burned
    uint256 _burnAmount = totalSupply.sub(_newTotalSupply);
    // leave remaining balance for company to be claimed at later date
    balances[this] = balances[this].sub(_burnAmount);
    Burn(this, _burnAmount);
    // allow our fountain contract to transfer the company tokens to itself
    allowed[this][fountainContractAddress] = companyTokens;
    Approval(this, fountainContractAddress, companyTokens);
    // set new totalSupply
    totalSupply = _newTotalSupply;
    // prevent this function from ever running again after finalizing the token sale
    tokenSaleActive = false;
    // dispatch event showing sale is finished
    TokenSaleFinished(
      totalSupply,
      _distributedTokens,
      bonusTokens,
      companyTokens
    );
    // everything went well return true
    return true;
  }

  // fallback function - do not allow any eth transfers to this contract
  function()
    external
  {
    revert();
  }

}
