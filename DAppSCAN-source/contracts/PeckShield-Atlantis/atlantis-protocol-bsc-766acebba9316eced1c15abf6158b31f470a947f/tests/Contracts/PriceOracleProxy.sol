pragma solidity ^0.5.16;

import "../../contracts/ABep20.sol";
import "../../contracts/AToken.sol";
import "../../contracts/PriceOracle.sol";

interface V1PriceOracleInterface {
    function assetPrices(address asset) external view returns (uint);
}

contract PriceOracleProxy is PriceOracle {
    /// @notice Indicator that this is a PriceOracle contract (for inspection)
    bool public constant isPriceOracle = true;

    /// @notice The v1 price oracle, which will continue to serve prices for v1 assets
    V1PriceOracleInterface public v1PriceOracle;

    /// @notice Address of the guardian, which may set the SAI price once
    address public guardian;

    /// @notice Address of the aBNB contract, which has a constant price
    address public aBNBAddress;

    /// @notice Address of the aUSDC contract, which we hand pick a key for
    address public cUsdcAddress;

    /// @notice Address of the aUSDT contract, which uses the aUSDC price
    address public cUsdtAddress;

    /// @notice Address of the aSAI contract, which may have its price set
    address public cSaiAddress;

    /// @notice Address of the aDAI contract, which we hand pick a key for
    address public cDaiAddress;

    /// @notice Handpicked key for USDC
    address public constant usdcOracleKey = address(1);

    /// @notice Handpicked key for DAI
    address public constant daiOracleKey = address(2);

    /// @notice Frozen SAI price (or 0 if not set yet)
    uint public saiPrice;

    /**
     * @param guardian_ The address of the guardian, which may set the SAI price once
     * @param v1PriceOracle_ The address of the v1 price oracle, which will continue to operate and hold prices for collateral assets
     * @param aBNBAddress_ The address of aBNB, which will return a constant 1e18, since all prices relative to ether
     * @param cUsdcAddress_ The address of aUSDC, which will be read from a special oracle key
     * @param cSaiAddress_ The address of aSAI, which may be read directly from storage
     * @param cDaiAddress_ The address of aDAI, which will be read from a special oracle key
     * @param cUsdtAddress_ The address of aUSDT, which uses the aUSDC price
     */
    constructor(address guardian_,
                address v1PriceOracle_,
                address aBNBAddress_,
                address cUsdcAddress_,
                address cSaiAddress_,
                address cDaiAddress_,
                address cUsdtAddress_) public {
        guardian = guardian_;
        v1PriceOracle = V1PriceOracleInterface(v1PriceOracle_);

        aBNBAddress = aBNBAddress_;
        cUsdcAddress = cUsdcAddress_;
        cSaiAddress = cSaiAddress_;
        cDaiAddress = cDaiAddress_;
        cUsdtAddress = cUsdtAddress_;
    }

    /**
     * @notice Get the underlying price of a listed aToken asset
     * @param aToken The aToken to get the underlying price of
     * @return The underlying asset price mantissa (scaled by 1e18)
     */
    function getUnderlyingPrice(AToken aToken) public view returns (uint) {
        address aTokenAddress = address(aToken);

        if (aTokenAddress == aBNBAddress) {
            // ether always worth 1
            return 1e18;
        }

        if (aTokenAddress == cUsdcAddress || aTokenAddress == cUsdtAddress) {
            return v1PriceOracle.assetPrices(usdcOracleKey);
        }

        if (aTokenAddress == cDaiAddress) {
            return v1PriceOracle.assetPrices(daiOracleKey);
        }

        if (aTokenAddress == cSaiAddress) {
            // use the frozen SAI price if set, otherwise use the DAI price
            return saiPrice > 0 ? saiPrice : v1PriceOracle.assetPrices(daiOracleKey);
        }

        // otherwise just read from v1 oracle
        address underlying = ABep20(aTokenAddress).underlying();
        return v1PriceOracle.assetPrices(underlying);
    }

    /**
     * @notice Set the price of SAI, permanently
     * @param price The price for SAI
     */
    function setSaiPrice(uint price) public {
        require(msg.sender == guardian, "only guardian may set the SAI price");
        require(saiPrice == 0, "SAI price may only be set once");
        require(price < 0.1e18, "SAI price must be < 0.1 BNB");
        saiPrice = price;
    }
}
