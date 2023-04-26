pragma solidity ^0.4.10;

import "../common/Active.sol";
import "../token/FloatingSupplyToken.sol";
import "./ITokenGenerator.sol";
import "./IProduct.sol";
import "./IVendorManager.sol";
import "./VendorBase.sol";
import "../common/ICheckList.sol";

contract BonusStore is Active {

    event ProductBought(address indexed buyer, address indexed product, string clientId, uint256 price, uint32 paidUnits);
    
    /**@dev Manager that controls vendor validity */
    ICheckList public allowedProducts;

    /**@dev Token generator that give Ether to compensate bonus tokens */
    ITokenGenerator public generator;

    function BonusStore(ITokenGenerator _generator, ICheckList _allowedProducts) {
        generator = _generator;
        allowedProducts = _allowedProducts;
    }

    /**@dev allows to receive ether directly */
    function () payable {}

    /**@dev Sets fund to new one */
    function setTokenGenerator(ITokenGenerator newGenerator) public ownerOnly {
        generator = newGenerator;
    }

    /**@dev Buys specific product for Bonus Tokens. User should first call 'approve' on token contract */
    function buy(IProduct product, string clientId, uint32 units, uint256 currentPrice) activeOnly {
        require(allowedProducts.contains(product));

        //calculate the amount of tokens to pay
        uint256 etherAmount = units * currentPrice;
     
        uint256 tokenAmount = etherAmount * generator.tokenEtherRate();
        generator.bonusToken().transferFrom(msg.sender, this, tokenAmount);
        generator.bonusToken().burn(tokenAmount);
        
        //get ether from fund, this will throw if there is not enough ether in the fund, which is unlikely
        generator.requestEther(etherAmount);
        
        //call product.buy
        product.buy.value(etherAmount)(clientId, false, currentPrice);

        ProductBought(msg.sender, product, clientId, currentPrice, units);
    }
}