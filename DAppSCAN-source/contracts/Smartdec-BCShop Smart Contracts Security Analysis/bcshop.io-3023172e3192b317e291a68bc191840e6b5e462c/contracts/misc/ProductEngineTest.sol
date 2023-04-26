pragma solidity ^0.4.10;

import '../shop/VendorBase.sol';
import '../shop/IProductEngine.sol';
import '../common/SafeMathLib.sol';

/*
ProductEngine that performs actual work */
library ProductEngineTest {

    using SafeMathLib for uint256;
    event ProductBoughtEx(uint256 indexed id, address indexed buyer, string clientId, uint256 price, uint256 paidUnits);

    /**@dev 
    Calculates and returns payment details: how many units are bought, 
     what part of ether should be paid and what part should be returned to buyer  */
    function calculatePaymentDetails(IProductEngine.ProductData storage self, uint256 weiAmount, bool acceptLessUnits) 
        constant
        returns(uint256 unitsToBuy, uint256 etherToPay, uint256 etherToReturn) 
    {
        unitsToBuy = 10;
        etherToReturn = 0;
        etherToPay = weiAmount;
    } 

    /**@dev 
    Buy product. Send ether with this function in amount equal to desirable product quantity total price */
    function buy(
        IProductEngine.ProductData storage self, 
        string clientId, 
        bool acceptLessUnits, 
        uint256 currentPrice) 
    {
        //check for active flag and valid price
        require(self.isActive && currentPrice == self.price);        

        require(msg.value > 10000);

        //check time limit        
        //require((self.startTime == 0 || now > self.startTime) && (self.endTime == 0 || now < self.endTime));

        //how much units do we buy
        var (unitsToBuy, etherToPay, etherToReturn) = calculatePaymentDetails(self, msg.value, acceptLessUnits);

        //check if there is enough units to buy
        require(unitsToBuy > 0);

        //how much to send to both provider and vendor
        VendorBase vendorInfo = VendorBase(self.owner);
        uint256 etherToProvider = etherToPay;
        uint256 etherToVendor = 0;
     
        createPurchase(self, clientId, unitsToBuy);

        self.soldUnits = uint32(self.soldUnits + unitsToBuy);
        
        vendorInfo.vendorManager().provider().transfer(etherToProvider);        
        vendorInfo.vendor().transfer(etherToVendor);

    }

    /**@dev 
    Call this to return all previous overpays */
    function withdrawOverpay(IProductEngine.ProductData storage self) {
        uint amount = self.pendingWithdrawals[msg.sender];        
        self.pendingWithdrawals[msg.sender] = 0;

        if (!msg.sender.send(amount)) {
            self.pendingWithdrawals[msg.sender] = amount;
        }
    }
    
    /**@dev 
    Marks purchase with given id as delivered or not */
    function markAsDelivered(IProductEngine.ProductData storage self, uint256 purchaseId, bool state) {
        require(VendorBase(self.owner).owner() == msg.sender);
        require(purchaseId < self.purchases.length);
        self.purchases[purchaseId].delivered = state;
    }

    /**@dev 
    Changes parameters of product */
    function setParams(
        IProductEngine.ProductData storage self,
        string newName, 
        uint256 newPrice,         
        uint256 newMaxUnits,
        // bool newAllowFractions,
        // uint256 newStartTime,
        // uint256 newEndTime,
        bool newIsActive
    ) {
        // require(VendorBase(self.owner).owner() == msg.sender);

        // self.name = newName;
        // self.price = newPrice;
        // self.maxUnits = newMaxUnits;
        // self.allowFractions = newAllowFractions;
        // self.isActive = newIsActive;
        // self.startTime = newStartTime;
        // self.endTime = newEndTime;
    }

    /**@dev Creates new Purchase record */
    function createPurchase(IProductEngine.ProductData storage self, string clientId, uint256 paidUnits) 
        internal 
    {
        uint256 pid = self.purchases.length++;
        IProductEngine.Purchase storage p = self.purchases[pid];
        //p.id = pid;
        //p.buyer = msg.sender;
        //p.clientId = clientId;
        p.price = self.price;
        //p.paidUnits = paidUnits * 2;
        p.delivered = false;        
        ProductBoughtEx(self.purchases.length, msg.sender, clientId, self.price, paidUnits);
    }
}
