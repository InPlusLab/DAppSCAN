pragma solidity ^0.5.16;

import "./SafeMath.sol";
import "./Ownable.sol";

interface ETHMedianizerInterface {

   function read() external view returns(uint price);
}

 //This contract will be changed before adding ERC20 tokens that are not stable coin
contract HoldefiPrices is Ownable {

    using SafeMath for uint256;

    uint constant public priceDecimal = 10**18;
   
    mapping(address => uint) public assetPrices;

    ETHMedianizerInterface public ethMedianizer;

    event PriceChanged(address asset, uint newPrice);

    constructor(address newOwnerChanger, ETHMedianizerInterface ethMedianizerContract) public Ownable(newOwnerChanger) {
        ethMedianizer = ethMedianizerContract;
    }

    // Returns price of selected asset
    function getPrice(address asset) external view returns(uint price) {
    	if (asset == address(0)){
    		price = uint(ethMedianizer.read());
    	}
        else {
            price = assetPrices[asset];
        }
    }

     // TODO: This function should be internal for the first version of priceFeed
    function setPrice(address asset, uint newPrice) public onlyOwner {
        require (asset != address(0),'Price of ETH can not be changed');

        assetPrices[asset] = newPrice;
        emit PriceChanged(asset, newPrice);
    }

    // Called by owner to add new stable token at 1$ price
    function addStableCoin(address asset) public onlyOwner {
        setPrice(asset, priceDecimal);
    }
//    SWC-100-Function Default Visibility:L47-49
    function() payable external {
        revert();
    }
}