pragma solidity ^0.4.10;

import './TokenProduct.sol';
import './NamedVendor.sol';
import '../token/MintableToken.sol';

///Vendor that can sell only token products. Must be a token manager to operate correctly
contract TokenVendor is NamedVendor {

    MintableToken public token;

    uint8 public bronzeRewardTokens;
    uint8 public silverRewardTokens;
    uint8 public goldRewardTokens;
    uint8 public silverRewardDistance; //each x-th investor gets silver reward
    uint8 public goldRewardDistance; //each x-th investor gets gold reward

    function TokenVendor(
        string vendorName, 
        address vendorWallet,        
        uint8 bronzeReward,
        uint8 silverReward,
        uint8 goldReward,
        uint8 silverDistance,
        uint8 goldDistance) 
        NamedVendor(vendorName, vendorWallet, vendorWallet, 0) 
    {
        bronzeRewardTokens = bronzeReward;
        silverRewardTokens = silverReward;
        goldRewardTokens = goldReward;
        silverRewardDistance = silverDistance;
        goldRewardDistance = goldDistance;
    }
    
    /**@dev creates promo action with given name and positions limit, with no time boundaries */
    function quickCreatePromo(string name, uint256 maxPositions) 
        ownerOnly 
        returns (address) 
    {
        return createProduct(name, 0, true, maxPositions, false, 0, 0);
    }

    /**@dev Sets token to sell */
    function setToken(MintableToken tokenToSell) ownerOnly {
        token = tokenToSell;        
    }

    function createProductObject(
        uint256 id,
        string name, 
        uint256 unitPriceInWei, 
        bool isLimited, 
        uint256 maxQuantity, 
        bool allowFractions,
        uint256 purchaseStartTime, 
        uint256 purchaseEndTime
    )
        internal
        ownerOnly
        returns (Product)
    {
        require (address(token) != 0x0);

        Product p = new TokenProduct(
            token, 
            id, 
            name, 
            maxQuantity, 
            purchaseStartTime, 
            purchaseEndTime,
            bronzeRewardTokens,
            silverRewardTokens,
            goldRewardTokens,
            silverRewardDistance,
            goldRewardDistance);

        token.setMinter(p, true);
        return p;
    }
}