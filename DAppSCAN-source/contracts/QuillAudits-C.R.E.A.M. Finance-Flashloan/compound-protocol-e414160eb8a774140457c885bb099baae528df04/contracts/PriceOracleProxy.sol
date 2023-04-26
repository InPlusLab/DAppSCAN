pragma solidity ^0.5.16;

import "./CErc20.sol";
import "./CToken.sol";
import "./PriceOracle.sol";
import "./Exponential.sol";
import "./EIP20Interface.sol";

interface V1PriceOracleInterface {
    function assetPrices(address asset) external view returns (uint);
}

interface YSwapInterface {
    function get_virtual_price() external view returns (uint256);
}

interface YVaultInterface {
    function getPricePerFullShare() external view returns (uint256);
}

interface AggregatorInterface {
  function latestAnswer() external view returns (int256);
  function latestTimestamp() external view returns (uint256);
  function latestRound() external view returns (uint256);
  function getAnswer(uint256 roundId) external view returns (int256);
  function getTimestamp(uint256 roundId) external view returns (uint256);

  event AnswerUpdated(int256 indexed current, uint256 indexed roundId, uint256 timestamp);
  event NewRound(uint256 indexed roundId, address indexed startedBy);
}

contract PriceOracleProxy is PriceOracle, Exponential {
    address public admin;

    /// @notice Indicator that this is a PriceOracle contract (for inspection)
    bool public constant isPriceOracle = true;

    /// @notice The v1 price oracle, which will continue to serve prices for v1 assets
    V1PriceOracleInterface public v1PriceOracle;

    /// @notice Chainlink Aggregators
    mapping(address => AggregatorInterface) public aggregators;

    address public cEthAddress;
    address public cUsdcAddress;
    address public cYcrvAddress;
    address public cYYcrvAddress;
    address public cYethAddress;

    /**
     * @param admin_ The address of admin to set aggregators
     * @param v1PriceOracle_ The address of the v1 price oracle, which will continue to operate and hold prices for collateral assets
     * @param cEthAddress_ The address of cETH, which will return a constant 1e18, since all prices relative to ether
     * @param cUsdcAddress_ The address of cUSDC
     * @param cYcrvAddress_ The address of cYcrv
     * @param cYYcrvAddress_ The address of cYYcrv
     * @param cYethAddress_ The address of cYeth
     */
    constructor(address admin_,
                address v1PriceOracle_,
                address cEthAddress_,
                address cUsdcAddress_,
                address cYcrvAddress_,
                address cYYcrvAddress_,
                address cYethAddress_) public {
        admin = admin_;
        v1PriceOracle = V1PriceOracleInterface(v1PriceOracle_);
        cEthAddress = cEthAddress_;
        cUsdcAddress = cUsdcAddress_;
        cYcrvAddress = cYcrvAddress_;
        cYYcrvAddress = cYYcrvAddress_;
        cYethAddress = cYethAddress_;
    }

    /**
     * @notice Get the underlying price of a listed cToken asset
     * @param cToken The cToken to get the underlying price of
     * @return The underlying asset price mantissa (scaled by 1e18)
     */
    function getUnderlyingPrice(CToken cToken) public view returns (uint) {
        address cTokenAddress = address(cToken);

        if (cTokenAddress == cEthAddress) {
            // ether always worth 1
            return 1e18;
        }

        if (cTokenAddress == cYethAddress) {
            uint yVaultPrice = YVaultInterface(0xe1237aA7f535b0CC33Fd973D66cBf830354D16c7).getPricePerFullShare();
            if (yVaultPrice == 0) {
                return getPriceFromV1(cTokenAddress);
            }
            return yVaultPrice;
        }

        if (cTokenAddress == cYcrvAddress || cTokenAddress == cYYcrvAddress) {
            MathError mathErr;
            Exp memory ethUsdPrice;
            Exp memory yCrvPrice;

            // ETH/USDC (treat USDC as USD)
            ethUsdPrice.mantissa = getUnderlyingPrice(CToken(cUsdcAddress)) / 1e12;
            if (ethUsdPrice.mantissa == 0) {
              return 0;
            }

            // YCRV/USD
            uint virtualPrice = YSwapInterface(0x45F783CCE6B7FF23B2ab2D70e416cdb7D6055f51).get_virtual_price();

            // YCRV/ETH = USD/ETH * YCRV/USD
            (mathErr, yCrvPrice) = mulExp(ethUsdPrice, Exp({mantissa: virtualPrice}));
            if (mathErr != MathError.NO_ERROR) {
                // Fallback to v1 PriceOracle
                return getPriceFromV1(cTokenAddress);
            }

            if (cTokenAddress == cYYcrvAddress) {
                uint yVaultPrice = YVaultInterface(0x5dbcF33D8c2E976c6b560249878e6F1491Bca25c).getPricePerFullShare();
                Exp memory yyCrvPrice;
                (mathErr, yyCrvPrice) = mulExp(yCrvPrice, Exp({mantissa: yVaultPrice}));
                if (mathErr != MathError.NO_ERROR) {
                    // Fallback to v1 PriceOracle
                    return getPriceFromV1(cTokenAddress);
                }
                return yyCrvPrice.mantissa;
            }
            return yCrvPrice.mantissa;
        }

        AggregatorInterface aggregator = aggregators[cTokenAddress];
        if (address(aggregator) != address(0)) {
            MathError mathErr;
            Exp memory price;
            (mathErr, price) = getPriceFromChainlink(aggregator);
            if (mathErr != MathError.NO_ERROR) {
                // Fallback to v1 PriceOracle
                return getPriceFromV1(cTokenAddress);
            }

            if (price.mantissa == 0) {
                return getPriceFromV1(cTokenAddress);
            }

            uint underlyingDecimals;
            underlyingDecimals = EIP20Interface(CErc20(cTokenAddress).underlying()).decimals();
            (mathErr, price) = mulScalar(price, 10**(18 - underlyingDecimals));
            if (mathErr != MathError.NO_ERROR ) {
                // Fallback to v1 PriceOracle
                return getPriceFromV1(cTokenAddress);
            }

            return price.mantissa;
        }

        return getPriceFromV1(cTokenAddress);
    }

    function getPriceFromChainlink(AggregatorInterface aggregator) internal view returns (MathError, Exp memory) {
        int256 chainLinkPrice = aggregator.latestAnswer();
        if (chainLinkPrice <= 0) {
            return (MathError.INTEGER_OVERFLOW, Exp({mantissa: 0}));
        }
        return (MathError.NO_ERROR, Exp({mantissa: uint(chainLinkPrice)}));
    }

    function getPriceFromV1(address cTokenAddress) internal view returns (uint) {
        address underlying = CErc20(cTokenAddress).underlying();
        return v1PriceOracle.assetPrices(underlying);
    }

    event AggregatorUpdated(address cTokenAddress, address source);

    function _setAggregators(address[] calldata cTokenAddresses, address[] calldata sources) external {
        require(msg.sender == admin, "only the admin may set the aggregators");
        for (uint i = 0; i < cTokenAddresses.length; i++) {
            aggregators[cTokenAddresses[i]] = AggregatorInterface(sources[i]);
            emit AggregatorUpdated(cTokenAddresses[i], sources[i]);
        }
    }
}
