pragma solidity >=0.4.24;

import "./AllowanceSheet.sol";
import "./BalanceSheet.sol";

/**
* @title TokenStorage
*/
contract TokenStorage {
    /**
        Storage
    */
    BalanceSheet public balances;
    AllowanceSheet public allowances;


    string public name;   //name of Token                
    uint8  public decimals;        //decimals of Token        
    string public symbol;   //Symbol of Token

    /**
    * @dev a TokenStorage consumer can set its storages only once, on construction
    *
    **/
    constructor (address _balances, address _allowances, string _name, uint8 _decimals, string _symbol) public {
        balances = BalanceSheet(_balances);
        allowances = AllowanceSheet(_allowances);

        name = _name;
        decimals = _decimals;
        symbol = _symbol;
    }

    /**
    * @dev claim ownership of balance sheet passed into constructor.
    **/
    function claimBalanceOwnership() public {
        balances.claimOwnership();
    }

    /**
    * @dev claim ownership of allowance sheet passed into constructor.
    **/
    function claimAllowanceOwnership() public {
        allowances.claimOwnership();
    }
}