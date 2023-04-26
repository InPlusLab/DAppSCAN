pragma solidity ^0.5.0;
// AT MAINNET ADDRESS: 0x02557a5E05DeFeFFD4cAe6D83eA3d173B272c904
contract CompoundOracleInterface {
    // returns asset:eth -- to get USDC:eth, have to do 10**24/result,


    constructor() public {
    }

    /**
  * @notice retrieves price of an asset
  * @dev function to get price for an asset
  * @param asset Asset for which to get the price
  * @return uint mantissa of asset price (scaled by 1e18) or zero if unset or contract paused
  */
    function getPrice(address asset) public view returns (uint);
    // function getPrice(address asset) public view returns (uint) {
    //     return 527557000000000;
    // }

}
