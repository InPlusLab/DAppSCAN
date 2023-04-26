pragma solidity >=0.4.21 <0.6.0;


import "../erc20/ERC20Impl.sol";

contract TestERC20 is ERC20Base{

    constructor(
        string memory _tokenName,
        uint8 _decimalUnits,
        string memory _tokenSymbol
    )  public ERC20Base(ERC20Base(0x0), 0, _tokenName,
    _decimalUnits, _tokenSymbol, true){}

  function generateTokens(address _owner, uint _amount) public returns(bool){
    return _generateTokens(_owner, _amount);
  }
  function destroyTokens(address _owner, uint _amount) public returns(bool){
    return _destroyTokens(_owner, _amount);
  }
  function enableTransfers(bool _transfersEnabled) public {
    _enableTransfers(_transfersEnabled);
  }
}
