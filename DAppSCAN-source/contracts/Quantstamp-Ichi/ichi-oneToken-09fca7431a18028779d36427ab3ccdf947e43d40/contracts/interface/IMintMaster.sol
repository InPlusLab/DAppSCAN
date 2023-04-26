// SPDX-License-Identifier: Unlicensed

pragma solidity 0.7.6;

import "./IModule.sol";

interface IMintMaster is IModule {
    
    function oneTokenOracles(address) external view returns(address);
    function init(address oneTokenOracle) external;
    function updateMintingRatio(address collateralToken) external returns(uint ratio, uint maxOrderVolume);
    function getMintingRatio(address collateral) external view returns(uint ratio, uint maxOrderVolume);
    function getMintingRatio2(address oneToken, address collateralToken) external view returns(uint ratio, uint maxOrderVolume);  
    function getMintingRatio4(address oneToken, address oneTokenOracle, address collateralToken, address collateralOracle) external view returns(uint ratio, uint maxOrderVolume); 
}
