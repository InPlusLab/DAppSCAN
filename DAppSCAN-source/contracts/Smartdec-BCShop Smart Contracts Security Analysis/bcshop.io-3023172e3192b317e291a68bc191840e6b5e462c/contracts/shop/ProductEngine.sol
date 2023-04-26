pragma solidity ^0.4.10;

import './VendorBase.sol';
import './IProductEngine.sol';
import '../common/SafeMathLib.sol';

/*
ProductEngine that performs actual work */
library ProductEngine {

    using SafeMathLib for uint256;

    //event ProductBought(address buyer, uint32 unitsToBuy, string clientId);
    //event that is emitted during purchase process. Id is 0-based index of purchase in the engine.purchases array
    event ProductBoughtEx(uint256 indexed id, address indexed buyer, string clientId, uint256 price, uint256 paidUnits);

    /**@dev 
    Calculates and returns payment details: how many units are bought, 
     what part of ether should be paid and what part should be returned to buyer  */
    function calculatePaymentDetails(IProductEngine.ProductData storage self, uint256 weiAmount, bool acceptLessUnits) 
        public
        constant
        returns(uint256 unitsToBuy, uint256 etherToPay, uint256 etherToReturn) 
    {        
        //unitsToBuy = weiAmount.safeDiv(self.price);
        unitsToBuy = weiAmount.safeMult(self.denominator).safeDiv(self.price);
        
        //if product is limited and it's not enough to buy, check acceptLessUnits flag
        if (self.maxUnits > 0 && self.soldUnits + unitsToBuy > self.maxUnits) {
            if (acceptLessUnits) {
                unitsToBuy = self.maxUnits - self.soldUnits;
            } else {
                unitsToBuy = 0; //set to 0 so it will fail in buy() function later
            }
        }
        
        etherToReturn = weiAmount.safeSub(self.price.safeMult(unitsToBuy).safeDiv(self.denominator));
        etherToPay = weiAmount.safeSub(etherToReturn);
    } 

    /**@dev 
    Buy product. Send ether with this function in amount equal to desirable product quantity total price */
    function buy(
        IProductEngine.ProductData storage self, 
        string clientId, 
        bool acceptLessUnits, 
        uint256 currentPrice
    ) 
        public
    {
        //check for active flag and valid price
        require(self.isActive && currentPrice == self.price); 

        //how much units do we buy
        var (unitsToBuy, etherToPay, etherToReturn) = calculatePaymentDetails(self, msg.value, acceptLessUnits);

        //store overpay to withdraw later
        if (etherToReturn > 0) {
            self.pendingWithdrawals[msg.sender] = self.pendingWithdrawals[msg.sender].safeAdd(etherToReturn);
        }

        //check if there is enough units to buy
        require(unitsToBuy > 0);

        //how much to send to both provider and vendor
        VendorBase vendorInfo = VendorBase(self.owner);
        uint256 etherToProvider;
        uint256 etherToVendor;
        if (etherToPay > 0) {
            etherToProvider = etherToPay.safeMult(vendorInfo.providerFeePromille()) / 1000;        
            etherToVendor = etherToPay.safeSub(etherToProvider);
        } else {
            etherToProvider = 0;
            etherToVendor = 0;
        }

        uint256 pid = self.purchases.length++;
        IProductEngine.Purchase storage p = self.purchases[pid];
        p.id = pid;
        p.buyer = msg.sender;
        p.clientId = clientId;
        p.price = self.price;
        p.paidUnits = unitsToBuy;
        p.delivered = false;

        if (self.userRating[msg.sender] == 0) {
            self.userRating[msg.sender] = pid + 1;
        }

        self.soldUnits = self.soldUnits + unitsToBuy;
        
        vendorInfo.vendorManager().provider().transfer(etherToProvider);        
        vendorInfo.vendor().transfer(etherToVendor);

        ProductBoughtEx(self.purchases.length - 1, msg.sender, clientId, self.price, unitsToBuy);
        //ProductBought(msg.sender, uint32(unitsToBuy), clientId);
    }

    /**@dev 
    Call this to return all previous overpays */
    function withdrawOverpay(IProductEngine.ProductData storage self) public {
        uint amount = self.pendingWithdrawals[msg.sender];        
        self.pendingWithdrawals[msg.sender] = 0;

        if (!msg.sender.send(amount)) {
            self.pendingWithdrawals[msg.sender] = amount;
        }
    }
    
    /**@dev 
    Marks purchase with given id as delivered or not */
    function markAsDelivered(IProductEngine.ProductData storage self, uint256 purchaseId, bool state) public {
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
        bool newIsActive
    )
        public
    {
        require(VendorBase(self.owner).owner() == msg.sender);

        self.name = newName;
        self.price = newPrice;
        self.maxUnits = newMaxUnits;        
        self.isActive = newIsActive;        
    }

    /**@dev Changes product rating. */
    function changeRating(IProductEngine.ProductData storage self, bool newLikeState) public {
        require(self.userRating[msg.sender] > 0);

        self.purchases[self.userRating[msg.sender] - 1].badRating = !newLikeState;
    }
}





