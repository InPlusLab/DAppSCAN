pragma solidity ^0.4.18;

import "./IDiscountPolicy.sol";
import "../common/SafeMathLib.sol";
import "../common/Active.sol";
import "../shop/IWallet.sol";
import "../token/IERC20Token.sol";
import "../common/EtherHolder.sol";

/**@dev 
Discount settings that calcultes cashback for token holders. Also stores accumulated cashback for each holder */
contract DiscountPolicy is Active, EtherHolder, IDiscountPolicy {

    using SafeMathLib for uint256;

    //
    // Events
    event CashbackCalculated(address indexed customer, uint256 amount);
    event CashbackAdded(address indexed customer, uint256 amount);


    //
    // Storage data
    uint256[] public levelTokens;       // how many tokens user needs to get the corresponding level of discount
    uint16[] public levelPcts;           // multiplier for standard discount 1/Y of pool for each level
    uint256 public minPoolBalance;      // minimum discount pool balance that enables discounts
    uint256 public discountsInPool;     // 1/discountsInPool is a share of pool for a single discount
    uint256 public maxDiscountPermille; // maximum discount permile [0-1000] 
    IWallet public pool;                // discount pool
    IERC20Token public token;           // token to check minimum token balance
    mapping(address => uint256) public totalCashback; //accumulated cashback amount for each holder



    //
    // Methods

    function DiscountPolicy(
        uint256 _minPoolBalance, 
        uint256 _discountsInPool, 
        uint256 _maxDiscountPermille, 
        IWallet _pool,
        IERC20Token _token,
        uint256[] _levelTokens,
        uint16[] _levelPcts
    ) 
        public 
    {
        setParams(_minPoolBalance, _discountsInPool, _maxDiscountPermille, _pool, _token, _levelTokens, _levelPcts);
    }


    /**@dev Returns cashback level % of specific customer  */
    function getLevelPct(address customer) public constant returns(uint16) {
        uint256 tokens = token.balanceOf(customer);
        
        if(tokens < levelTokens[0]) {
            return 0;
        }
        uint256 i;
        for(i = 0; i < levelTokens.length - 1; ++i) {
            if(tokens < levelTokens[i + 1]) {
                return levelPcts[i];
            }
        }

        return levelPcts[i];
    }


    /**@dev Returns discount for specific amount and buyer */
    function getCustomerDiscount(address customer, uint256 amount) public constant returns(uint256) {
        uint16 levelPct = getLevelPct(customer);

        if(levelPct > 0) {
            uint256 poolBalance = pool.getBalance();
            
            if(poolBalance >= minPoolBalance) {
                uint256 discount = poolBalance * levelPct / (discountsInPool * 100);
                uint256 maxDiscount = amount * maxDiscountPermille / 1000;
                
                return discount < maxDiscount ? discount : maxDiscount;
            }
        }
        return 0;
    }
    

    /**@dev Transfers discount to the sender, returns discount amount*/
    function requestCustomerDiscount(address customer, uint256 amount) 
        public 
        managerOnly
        returns(uint256)
    {
        uint256 discount = getCustomerDiscount(customer, amount);
        if(discount > 0) {
            //accumulate discount
            pool.withdrawTo(this, discount);
            CashbackCalculated(customer, discount);

            //Don't add the cashback here. it will be calculated later by oracle once a certain period
            //totalCashback[customer] = totalCashback[customer].safeAdd(discount);            
        }
        return discount;
    }


    /**@dev transfer user's cashback to his wallet */
    function withdrawCashback() public activeOnly {
        uint256 amount = totalCashback[msg.sender];        
        totalCashback[msg.sender] = 0;
        
        msg.sender.transfer(amount);
    }


    /**@dev Adds a certain amount to a customer's cashback */
    function addCashbacks(address[] customers, uint256[] amounts) public managerOnly {
        require(customers.length == amounts.length);

        for(uint256 i = 0; i < customers.length; ++i) {
            totalCashback[customers[i]] = totalCashback[customers[i]].safeAdd(amounts[i]);
            CashbackAdded(customers[i], amounts[i]); 
        }
    }


    function setParams(
        uint256 _minPoolBalance, 
        uint256 _discountsInPool, 
        uint256 _maxDiscountPermille, 
        IWallet _pool,
        IERC20Token _token,
        uint256[] _levelTokens,
        uint16[] _levelPcts
    ) 
        public 
        ownerOnly
    {
        minPoolBalance = _minPoolBalance;
        discountsInPool = _discountsInPool;
        maxDiscountPermille = _maxDiscountPermille;
        pool = _pool;
        token = _token;
        levelTokens = _levelTokens;
        levelPcts = _levelPcts;

        require(paramsValid());
    }

    function paramsValid() internal constant returns (bool) {
        if(maxDiscountPermille > 1000) {
            return false;
        }
        
        if (levelTokens.length == 0 || levelTokens.length > 10 || levelPcts.length != levelTokens.length) {
            return false;
        }        

        for (uint256 i = 0; i < levelTokens.length - 1; ++i) {
            if (levelTokens[i] >= levelTokens[i + 1]) {
                return false;
            }
            if (levelPcts[i] >= levelPcts[i + 1]) {
                return false;
            }
        }
        return true;
    }


    function () public payable {}
}