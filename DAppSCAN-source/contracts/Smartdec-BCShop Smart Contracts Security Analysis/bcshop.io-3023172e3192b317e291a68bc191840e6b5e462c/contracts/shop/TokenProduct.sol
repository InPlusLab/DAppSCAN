pragma solidity ^0.4.18;

import "./Product.sol";
import "../token/MintableToken.sol";

/**@dev Product that mints tokens at the moment of purchase */
contract TokenProduct is Product {  
    
    MintableToken token;

    function TokenProduct(        
        string productName,
        uint256 unitPriceInWei,
        uint256 maxProductUnits,
        MintableToken mintableToken
    ) 
    Product(productName, unitPriceInWei, maxProductUnits, uint256(10) ** mintableToken.decimals())
    public {
        token = mintableToken;
    }

    /**@dev 
    Buy product. */
    function buy(string clientId, bool acceptLessUnits, uint256 currentPrice) public payable 
    {        
        super.buy(clientId, acceptLessUnits, currentPrice);

        //check last purchase for paidUnits info
        IProductEngine.Purchase storage lastPurchase = engine.purchases[engine.purchases.length - 1];
        token.mint(msg.sender, lastPurchase.paidUnits);
    }
}