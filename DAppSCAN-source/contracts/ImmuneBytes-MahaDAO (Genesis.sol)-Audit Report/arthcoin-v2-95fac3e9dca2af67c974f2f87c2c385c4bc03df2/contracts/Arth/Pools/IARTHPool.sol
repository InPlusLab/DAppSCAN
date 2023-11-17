// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IARTHPool {
    function repay(uint256 amount) external;

    function borrow(uint256 amount) external;

    function setStabilityFee(uint256 percent) external;

    function setBuyBackCollateralBuffer(uint256 percent) external;

    function setCollatETHOracle(
        address collateralWETHOracleAddress,
        address wethAddress
    ) external;

    function toggleMinting() external;

    function toggleRedeeming() external;

    function toggleRecollateralize() external;

    function toggleBuyBack() external;

    function toggleCollateralPrice(uint256 newPrice) external;

    function setPoolParameters(
        uint256 newCeiling,
        uint256 newRedemptionDelay,
        uint256 newMintFee,
        uint256 newRedeemFee,
        uint256 newBuybackFee,
        uint256 newRecollateralizeFee
    ) external;

    function setTimelock(address newTimelock) external;

    function setOwner(address ownerAddress) external;

    function mint1t1ARTH(uint256 collateralAmount, uint256 ARTHOutMin)
        external
        returns (uint256);

    function mintAlgorithmicARTH(uint256 arthxAmountD18, uint256 arthOutMin)
        external
        returns (uint256);

    function mintFractionalARTH(
        uint256 collateralAmount,
        uint256 arthxAmount,
        uint256 ARTHOutMin
    ) external returns (uint256);

    function redeem1t1ARTH(uint256 arthAmount, uint256 collateralOutMin)
        external;

    function redeemFractionalARTH(
        uint256 arthAmount,
        uint256 arthxOutMin,
        uint256 collateralOutMin
    ) external;

    function redeemAlgorithmicARTH(uint256 arthAmounnt, uint256 arthxOutMin)
        external;

    function collectRedemption() external;

    function recollateralizeARTH(uint256 collateralAmount, uint256 arthxOutMin)
        external
        returns (uint256);

    function buyBackARTHX(uint256 arthxAmount, uint256 collateralOutMin)
        external;

    function getGlobalCR() external view returns (uint256);

    function mintingFee() external returns (uint256);

    function redemptionFee() external returns (uint256);

    function buybackFee() external returns (uint256);

    function getRecollateralizationDiscount() external view returns (uint256);

    function recollatFee() external returns (uint256);

    function getCollateralGMUBalance() external view returns (uint256);

    function getAvailableExcessCollateralDV() external view returns (uint256);

    function getCollateralPrice() external view returns (uint256);

    function getARTHMAHAPrice() external view returns (uint256);

    function collateralPricePaused() external view returns (bool);

    function pausedPrice() external view returns (uint256);

    function collateralETHOracleAddress() external view returns (address);
}
