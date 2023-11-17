// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

interface IARTHController {
    function toggleCollateralRatio() external;

    function refreshCollateralRatio() external;

    function addPool(address pool_address) external;

    function removePool(address pool_address) external;

    function getARTHInfo()
        external
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256
        );

    function setMintingFee(uint256 fee) external;

    function setARTHXETHOracle(
        address _arthxOracleAddress,
        address _wethAddress
    ) external;

    function setARTHETHOracle(address _arthOracleAddress, address _wethAddress)
        external;

    function setArthStep(uint256 newStep) external;

    function setRedemptionFee(uint256 fee) external;

    function setOwner(address _ownerAddress) external;

    function setPriceBand(uint256 _priceBand) external;

    function setTimelock(address newTimelock) external;

    function setPriceTarget(uint256 newPriceTarget) external;

    function setARTHXAddress(address _arthxAddress) external;

    function setRefreshCooldown(uint256 newCooldown) external;

    function setETHGMUOracle(address _ethGMUConsumerAddress) external;

    function setGlobalCollateralRatio(uint256 _globalCollateralRatio) external;

    function getRefreshCooldown() external view returns (uint256);

    function getARTHPrice() external view returns (uint256);

    function getARTHXPrice() external view returns (uint256);

    function getETHGMUPrice() external view returns (uint256);

    function getGlobalCollateralRatio() external view returns (uint256);

    function getGlobalCollateralValue() external view returns (uint256);

    function arthPools(address pool) external view returns (bool);

    function toggleUseGlobalCRForMint(bool flag) external;

    function toggleUseGlobalCRForRecollateralize(bool flag) external;

    function setMintCollateralRatio(uint256 val) external;

    function setRedeemCollateralRatio(uint256 val) external;

    function toggleUseGlobalCRForRedeem(bool flag) external;

    function setRecollateralizeCollateralRatio(uint256 val) external;

    function getCRForMint() external view returns(uint256);

    function getCRForRedeem() external view returns(uint256);

    function getCRForRecollateralize() external view returns(uint256);
}
