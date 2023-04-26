pragma solidity ^0.4.18;

import "../common/Manageable.sol";
import "./IProductStorage.sol";
import "../common/SafeMathLib.sol";

/**dev not used now, merged with ProductPayment */
contract Escrow is Manageable {

    using SafeMathLib for uint256;

    //
    // Inner Types


	
    //
    // Events



    //
    // Storage data    

    uint256 public holdTime; //payment hold time in seconds
    IProductStorage public productStorage;


    //
    // Modifiers



    //
    // Methods

    function Escrow(IProductStorage _productStorage, uint256 _holdTimeHours) public {
        productStorage = _productStorage;
        holdTime = _holdTimeHours * 1 hours;
    }    

    /**@dev Allows to receive ETH */
    function() payable {}

    /**@dev Adds payment info. this funcion should carry ETH equal to fee+profit */
    function addPayment(uint256 productId, uint256 purchaseId, address customer, uint256 fee, uint256 profit) 
        public 
        payable
        managerOnly 
    {
        require(msg.value == fee + profit);

        //if product doesn't support escrow setEscrowData will throw exception        
        productStorage.setEscrowData(productId, purchaseId, customer, fee, profit, now);    
    }

    /**@dev Make a complain on purchase, only customer can call this method */
    function complain(uint256 productId, uint256 purchaseId) public {
        //check product's escrow option
        require(productStorage.isEscrowUsed(productId));

        var (customer, fee, profit, timestamp) = productStorage.getEscrowData(productId, purchaseId);
        
        //check valid customer
        require(customer == msg.sender);        
        //check complain time
        require(timestamp + holdTime > now);

        //change purchase status
        productStorage.changePurchase(productId, purchaseId, IProductStorage.PurchaseState.Complain);        
    }

    /**@dev Resolves a complain on specific purchase. 
    If cancelPayment is true, payment returns to customer; otherwise - to the vendor */
    function resolve(uint256 productId, uint256 purchaseId, bool cancelPayment) public managerOnly {
        
        //check purchase state
        require(productStorage.getPurchase(productId, purchaseId) == IProductStorage.PurchaseState.Complain);
        
        var (customer, fee, profit, timestamp) = productStorage.getEscrowData(productId, purchaseId);
        
        if(cancelPayment) {            
            productStorage.changePurchase(productId, purchaseId, IProductStorage.PurchaseState.Canceled);
            //transfer to customer
            customer.transfer(fee.safeAdd(profit));
        } else {
            productStorage.changePurchase(productId, purchaseId, IProductStorage.PurchaseState.Pending);

        }
    }
}