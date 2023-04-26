pragma solidity ^0.4.24;

contract ITwoKeyAdmin {
    function getDefaultIntegratorFeePercent() public view returns (uint);
    function getDefaultNetworkTaxPercent() public view returns (uint);
    function getTwoKeyRewardsReleaseDate() external view returns(uint);
}

