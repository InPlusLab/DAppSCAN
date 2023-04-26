pragma solidity ^0.4.17;
import 'zeppelin-solidity/contracts/token/ERC827/ERC827Token.sol';
import 'zeppelin-solidity/contracts/ownership/Ownable.sol';
    
contract ZipToken827 is ERC827Token, Ownable {
    string public constant NAME = "ZipperToken";
    string public constant SYMBOL = "ZIPT";
    uint8 public constant DECIMALS = 18;
    uint public constant TOTAL_TOKEN_AMOUNT = 1000000000;
    uint public constant INITIAL_SUPPLY = TOTAL_TOKEN_AMOUNT * 10**uint(DECIMALS);
    bool public filled = false;

    function ZipToken827() public {
        totalSupply_ = INITIAL_SUPPLY;
        balances[msg.sender] = INITIAL_SUPPLY;
    }

    function distributeTokens(address[] addresses, uint[] values) public onlyOwner {
        require(addresses.length == values.length);
        for (uint i = 0; i < addresses.length; i++) {
            address a = addresses[i];
            uint v = values[i];
            if (balanceOf(a) == 0) {
                transfer(a, v);
            }
        }
    }
}
