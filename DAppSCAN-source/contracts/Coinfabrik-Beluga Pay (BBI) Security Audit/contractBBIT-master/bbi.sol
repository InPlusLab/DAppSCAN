pragma solidity 0.4.19;

import './safeMath.sol';
import './erc20.sol';

/*
 * BelugaPay ICO contract
 * Updated date : 12-feb-2018
 *
 */

contract BBIToken is StandardToken {

    string public name = "Beluga Banking Infrastructure Token";
    string public symbol = "BBI";
    
    uint  public decimals    = 18;   
    uint  public totalUsed   = 0;
    uint  public etherRaised = 0;
    
    uint  public etherCap    = 30000e18;  // 30K Ether

    /*
    * production settings
    *  
    *   ICO     : 01-Mar-2018 - 31-Mar-2018
    *    
    */

    // ICO Start 1519862400    // 01-Mar-2018 00:00:00 hrs GMT
    uint public icoEndDate        = 1522540799;   // 31-Mar-2018 23:59:59 - GMT  
                                   
    uint constant SECONDS_IN_YEAR = 31536000;     // 365 * 24 * 60 * 60 ;

    // flag for emergency stop or start 
    bool public halted = false;              
    
    uint  public maxAvailableForSale    =  40000000e18;      // (44.44% - 40M) 
    uint  public tokensTeam             =  30000000e18;      // (33.33% -30M )
    uint  public tokensCommunity        =   5000000e18;      // (05.55% -5M )
    uint  public tokensMasterNodes      =   5000000e18;      // (05.55% -5M )
    uint  public tokensBankPartners     =   5000000e18;      // (05.55% - 5M ) 
    uint  public tokensDataProviders    =   5000000e18;      // (05.55% - 5M )

   /* 
   * team classification flag
   * for defining the lock period 
   *
   */ 

   uint constant teamInternal = 1;   // team and community
   uint constant teamPartners = 2;   // bank partner, data providers etc
   uint constant icoInvestors = 3;   // ico investors

    /*  
    *   the following are the testnet addresses
    *   should be updated with mainnet address
    *   before deploying the contract
    *   Note : rinkeby testnet addresses used here for testing
    */

    address public addressETHDeposit       = 0xcc85a2948DF9cfd5d06b2C926bA167562844395b;  //Deposit address

    address public addressTeam             = 0xB3C28227d2dd0FbF2838FeD192F38669B2169FE8;  //1
    address public addressCommunity        = 0xbDBE59910D8955F62543Cd35830263bE9C8D731D;  //2
    address public addressBankPartners     = 0xBc78914C15E382b9b3697Cd4352556F8da5fE2ae;  //3
    address public addressDataProviders    = 0x940dCDcd42666f18E229fe917C5c706ad2407C67;
    address public addressMasterNodes      = 0xB8686c1085f1F6e877fb52821f63d593ca2E845e;
   
    address public addressICOManager       = 0xACfF1E8824EFB2739abfE6Ed6c4ed8F697790d06; //4
     

    /*
    * Contract Constructor
    */


    function BBIToken() public {
            
                     totalSupply_ = 90000000e18 ;    // 90,000,000 - 90M;                 

                     balances[addressTeam] = tokensTeam;
                     balances[addressCommunity] = tokensCommunity;
                     balances[addressBankPartners] = tokensBankPartners;
                     balances[addressDataProviders] = tokensDataProviders;
                     balances[addressMasterNodes] = tokensMasterNodes;
                     balances[addressICOManager] = maxAvailableForSale;
                     
                     Transfer(this, addressTeam, tokensTeam);
                     Transfer(this, addressCommunity, tokensCommunity);
                     Transfer(this, addressBankPartners, tokensBankPartners);
                     Transfer(this, addressDataProviders, tokensDataProviders);
                     Transfer(this, addressMasterNodes, tokensMasterNodes);
                     Transfer(this, addressICOManager, maxAvailableForSale);
                  
            }
    
    /*
    *   Emergency Stop or Start ICO.
    *
    */

    function  halt() onlyManager public{
        require(msg.sender == addressICOManager);
        halted = true;
    }

    function  unhalt() onlyManager public {
        require(msg.sender == addressICOManager);
        halted = false;
    }

    /*
    *   Check whether ICO running or not.
    *
    */

    modifier onIcoRunning() {
        // Checks, if ICO is running and has not been stopped
        require( halted == false);
        _;
    }
   
    modifier onIcoStopped() {
        // Checks if ICO was stopped or deadline is reached
      require( halted == true);
        _;
    }

    modifier onlyManager() {
        // only ICO manager can do this action
        require(msg.sender == addressICOManager);
        _;
    }

    /*
     * ERC 20 Standard Token interface transfer function
     *
     * Prevent transfers until ICO period is over.
     * 
     * Transfer 
     *    - Allow 50% after six months for Community and Team
     *    - Allow all including (Dataproviders, MasterNodes, Bank) after one year
     *    - Allow Investors after ICO end date 
     *
     * Applicable tests:
     *
     * - Test restricted early transfer
     * - Test transfer after restricted period
     */


    function transfer(address _to, uint256 _value) public returns (bool success) 
    {
           if ( msg.sender == addressICOManager) { return super.transfer(_to, _value); }           
           
           // ICO investors can transfer after the ICO period
           if ( !halted && identifyAddress(msg.sender) == icoInvestors && now > icoEndDate ) { return super.transfer(_to, _value); }
           
           // Team and Community can transfer upto 50% of tokens after six months of ICO end date 
           if ( !halted && identifyAddress(msg.sender) == teamInternal && (SafeMath.add(balances[msg.sender], _value) < SafeMath.div(tokensTeam,2) ) && now > SafeMath.add(icoEndDate, SafeMath.div(SECONDS_IN_YEAR,2))) { return super.transfer(_to, _value); }            
           
           // All can transfer after a year from ICO end date 
           if ( !halted && now > SafeMath.add(icoEndDate , SECONDS_IN_YEAR)) { return super.transfer(_to, _value); }

        return false;
         
    }


    function transferFrom(address _from, address _to, uint256 _value) public returns (bool success) 
    {
           if ( msg.sender == addressICOManager) return super.transferFrom(_from,_to, _value);           
           if ( !halted && identifyAddress(msg.sender) == icoInvestors && now > icoEndDate ) return super.transferFrom(_from,_to, _value);
           if ( !halted && identifyAddress(msg.sender) == teamInternal && (SafeMath.add(balances[msg.sender], _value) < SafeMath.div(tokensTeam,2)) && now >SafeMath.add(icoEndDate, SafeMath.div(SECONDS_IN_YEAR,2)) ) return super.transferFrom(_from,_to, _value);            
           if ( !halted && now > SafeMath.add(icoEndDate, SECONDS_IN_YEAR)) return super.transferFrom(_from,_to, _value);
        return false;
    }

   function identifyAddress(address _buyer) constant public returns(uint) {
        if (_buyer == addressTeam || _buyer == addressCommunity) return teamInternal;
        if (_buyer == addressMasterNodes || _buyer == addressBankPartners || _buyer == addressDataProviders) return teamPartners;
             return icoInvestors;
    }

   
    /**
     * Destroy tokens
     * Remove `_value` tokens from the system irreversibly
     * @param _value the amount of money to burn
     */

    function  burn(uint256 _value)  onlyManager public returns (bool success) {
        require(balances[msg.sender] >= _value);   // Check if the sender has enough BBI
        balances[msg.sender] -= _value;            // Subtract from the sender
        totalSupply_ -= _value;                    // Updates totalSupply
        return true;
    }


    /*  
     *  main function for receiving the ETH from the investors 
     *  and transferring tokens after calculating the price 
     *  Buy quantity of tokens depending on the amount of sent ethers.
     *  _buyer Address of account which will receive tokens
     */    
    
    function buyBBITokens(address _buyer, uint256 _value) public {
            // prevent transfer to 0x0 address
            require(_buyer != 0x0);

            // msg value should be more than 0
            require(_value > 0);

            // if not halted
            require(!halted);

            // Now is before ICO end date 
            require(now < icoEndDate);

            // total tokens is price (1ETH = 960 tokens) multiplied by the ether value provided 
            // SWC-101-Integer Overflow and Underflow: L223
            uint tokens = (SafeMath.mul(_value, 960));

            // total used + tokens should be less than maximum available for sale
            require(SafeMath.add(totalUsed, tokens) < balances[addressICOManager]);

            // Ether raised + new value should be less than the Ether cap
            require(SafeMath.add(etherRaised, _value) < etherCap);
            
            balances[_buyer] = SafeMath.add( balances[_buyer], tokens);
           	balances[addressICOManager] = SafeMath.sub(balances[addressICOManager], tokens);
            totalUsed += tokens;            
            etherRaised += _value;  
      
            addressETHDeposit.transfer(_value);
  			Transfer(this, _buyer, tokens );
        }

     /*
     *  default fall back function      
     */
    //  SWC-105-Unprotected Ether Withdrawal: L243 - L245
    function () payable onIcoRunning public {
                buyBBITokens(msg.sender, msg.value);           
            }
}