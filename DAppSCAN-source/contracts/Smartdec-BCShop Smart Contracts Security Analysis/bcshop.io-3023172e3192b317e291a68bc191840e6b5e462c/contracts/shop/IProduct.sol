pragma solidity ^0.4.10;

import "../common/IOwned.sol";
import './IProductEngine.sol';

/**@dev Product abstraction with 'buy' method */
contract IProduct is IOwned {
    /**@dev 
    Buy product. Send ether with this function in amount equal to desirable product quantity total price
     * clientId - Buyer's product-specific information. 
     * acceptLessUnits - 'true' if buyer doesn't care of buying the exact amount of limited products.
     If N units left and buyer sends payment for N+1 units then settings this flag to 'true' will result in
     buying N units, while 'false' will simply decline transaction 
     * currentPrice - current product price as shown in 'price' property. 
     Used for security reasons to compare actual price with the price at the moment of transaction. 
     If they are not equal, transaction is declined  */
    function buy(string clientId, bool acceptLessUnits, uint256 currentPrice) public payable;
}
