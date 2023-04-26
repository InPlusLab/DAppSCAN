pragma solidity ^0.4.10;

/**@dev imitates real product functions to be able usable by bonus store */
contract FakeProduct {
    //Storage data of product
    struct ProductData {        
        address owner; //VendorBase - product's owner
        //uint32 id; //Product id        
        string name; //Name of the product        
        uint256 price; //Price of one product unit        
        uint32 maxUnits; //Max quantity of limited product units, or 0 if unlimited        
        //bool allowFractions; //True if product can be sold by fractions, like 2.5 units                
        bool isActive; //True if it is possible to buy a product        
        //uint256 startTime; //From this point a product is buyable (linux timestamp)        
        //uint256 endTime; //After this point the product is unbuyable (linux timestamp)        
        uint32 soldUnits; //How many units already sold        
    }

    address public owner;
    address public beneficiary;
    ProductData public engine;
    
    function FakeProduct(address _owner, address _beneficiary, string _name, uint256 _price) {
        owner = _owner;
        beneficiary = _beneficiary;

        engine.owner = owner;
        engine.name = _name;
        engine.price = _price;
        engine.isActive = true;        
    }

    function buy(string clientId, bool acceptLessUnits, uint256 currentPrice) public payable {
        beneficiary.transfer(msg.value);
    }

    function transferOwnership(address _newOwner) public {
    } 
}