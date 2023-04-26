pragma solidity ^0.4.18;

import "./IDiscountPolicy.sol";
import "../common/Manageable.sol";
import "../shop/IWallet.sol";
import "../token/IERC20Token.sol";

/**@dev 
Discount settings that calcultes discounts for token holders.
Applies only if user has at least minTokens amount and there is at least minPoolBalance ether in the pool.
Discount for a purcahse equals (pool balance / discountsInPool) but not exceeding maxDiscountPermille
of purchase amount.   */
contract DiscountPolicy is Manageable, IDiscountPolicy {

    //
    // Events



    //
    // Storage data
    uint256 public minTokens;           // minimum token amount for getting discount
    uint256 public minPoolBalance;      // minimum discount pool balance that enables discounts
    uint256 public discountsInPool;     // 1/discountsInPool is a share of pool for a single discount
    uint256 public maxDiscountPermille; // maximum discount permile [0-1000] 
    IWallet public pool;                // discount pool
    IERC20Token public token;           // token to check minimum token balance


    //
    // Methods

    function DiscountPolicy(
        uint256 _minPoolBalance, 
        uint256 _discountsInPool, 
        uint256 _maxDiscountPermille, 
        IWallet _pool,
        IERC20Token _token,
        uint256 _minTokens
    ) 
        public 
    {
        setParams(_minPoolBalance, _discountsInPool, _maxDiscountPermille, _pool, _token, _minTokens);
    }


    function setParams(
        uint256 _minPoolBalance, 
        uint256 _discountsInPool, 
        uint256 _maxDiscountPermille, 
        IWallet _pool,
        IERC20Token _token,
        uint256 _minTokens
    ) 
        public 
        ownerOnly
    {
        require(maxDiscountPermille <= 1000);

        minPoolBalance = _minPoolBalance;
        discountsInPool = _discountsInPool;
        maxDiscountPermille = _maxDiscountPermille;
        pool = _pool;
        token = _token;
        minTokens = _minTokens;
    }


    /**@dev Returns discount for specific amount and buyer */
    function getDiscount(address buyer, uint256 amount) public constant returns(uint256) {
        if(token.balanceOf(buyer) >= minTokens) {
            uint256 poolBalance = pool.getBalance();
            
            if(poolBalance > minPoolBalance) {
                uint256 discount = poolBalance / discountsInPool;
                uint256 maxDiscount = amount * maxDiscountPermille / 1000;
                
                return discount < maxDiscount ? discount : maxDiscount;
            }
        }
        return 0;
    }

    /**@dev Transfers discount to the sender, returns discount amount*/
    function requestDiscount(address buyer, uint256 amount) 
        public 
        managerOnly
        returns(uint256)
    {
        uint256 discount = getDiscount(buyer, amount);
        if(discount > 0) {
            pool.withdrawTo(msg.sender, discount);
        }
        return discount;
    }
}