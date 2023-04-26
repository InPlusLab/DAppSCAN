// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../price_getters/AbstractPriceGetter.sol";
import "../connectors/mstable/interfaces/IMasset.sol";
import "../connectors/mstable/interfaces/ISavingsContract.sol";

contract VimUsdPriceGetter is AbstractPriceGetter, Ownable {

    address public usdcToken;
    IMasset public mUsdToken;
    ISavingsContractV2 public imUsdToken;

    constructor(
        address _usdcToken,
        address _mUsdToken,
        address _imUsdToken
    ) {
        require(_usdcToken != address(0), "Zero address not allowed");
        require(_mUsdToken != address(0), "Zero address not allowed");
        require(_imUsdToken != address(0), "Zero address not allowed");

        usdcToken = _usdcToken;
        mUsdToken = IMasset(_mUsdToken);
        imUsdToken = ISavingsContractV2(_imUsdToken);
    }

    function getUsdcBuyPrice() external view override returns (uint256) {
        uint256 mintOutput = mUsdToken.getMintOutput(usdcToken, (10 ** 6));
        return (10 ** 36) / imUsdToken.underlyingToCredits(mintOutput);
    }

    function getUsdcSellPrice() external view override returns (uint256) {
        uint256 underlying = imUsdToken.creditsToUnderlying(10 ** 18);
        return mUsdToken.getRedeemOutput(usdcToken, underlying) * (10 ** 12);
    }
}
