pragma solidity ^0.5.16;
pragma experimental ABIEncoderV2;

import "./PriceOracle.sol";
import "./ABep20.sol";
import "./EIP20Interface.sol";
import "./SafeMath.sol";

interface IStdReference {
    /// A structure returned whenever someone requests for standard reference data.
    struct ReferenceData {
        uint256 rate; // base/quote exchange rate, multiplied by 1e18.
        uint256 lastUpdatedBase; // UNIX epoch of the last time when base price gets updated.
        uint256 lastUpdatedQuote; // UNIX epoch of the last time when quote price gets updated.
    }

    /// Returns the price data for the given base/quote pair. Revert if not available.
    function getReferenceData(string calldata _base, string calldata _quote) external view returns (ReferenceData memory);

    /// Similar to getReferenceData, but with multiple base/quote pairs at once.
    function getReferenceDataBulk(string[] calldata _bases, string[] calldata _quotes) external view returns (ReferenceData[] memory);
}

contract AtlantisPriceOracle is PriceOracle {
    using SafeMath for uint256;
    address public admin;

    mapping(address => uint) prices;
    event PricePosted(address asset, uint previousPriceMantissa, uint requestedPriceMantissa, uint newPriceMantissa);
    event NewAdmin(address oldAdmin, address newAdmin);

    IStdReference internal ref;

    constructor() public {
        admin = msg.sender;
    }

    function setRefAddress(IStdReference _ref) public {
        require(msg.sender == admin, "only admin can set ref address");
        ref = _ref;
    }

    function getRefAddress() public view returns (address) {
        return address(ref);
    }

    function getUnderlyingPrice(AToken aToken) public view returns (uint) {
        if (compareStrings(aToken.symbol(), "aBNB")) {
            IStdReference.ReferenceData memory data = ref.getReferenceData("BNB", "USD");
            return data.rate;
        }else if (compareStrings(aToken.symbol(), "ATL")) {
            return prices[address(aToken)];
        } else {
            uint256 price;
            EIP20Interface token = EIP20Interface(ABep20(address(aToken)).underlying());

            if(prices[address(token)] != 0) {
                price = prices[address(token)];
            } else {
                IStdReference.ReferenceData memory data = ref.getReferenceData(token.symbol(), "USD");
                price = data.rate;
            }

            uint decimalDelta = uint(18).sub(uint(token.decimals()));
            // Ensure that we don't multiply the result by 0
            if (decimalDelta > 0) {
                return price.mul(10**decimalDelta);
            } else {
                return price;
            }
        }
    }

    function setUnderlyingPrice(AToken aToken, uint underlyingPriceMantissa) public {
        require(msg.sender == admin, "only admin can set underlying price");
        address asset = address(ABep20(address(aToken)).underlying());
        emit PricePosted(asset, prices[asset], underlyingPriceMantissa, underlyingPriceMantissa);
        prices[asset] = underlyingPriceMantissa;
    }

    function setDirectPrice(address asset, uint price) public {
        require(msg.sender == admin, "only admin can set price");
        emit PricePosted(asset, prices[asset], price, price);
        prices[asset] = price;
    }

    function assetPrices(address asset) external view returns (uint) {
        return prices[asset];
    }

    function compareStrings(string memory a, string memory b) internal pure returns (bool) {
        return (keccak256(abi.encodePacked((a))) == keccak256(abi.encodePacked((b))));
    }

    function setAdmin(address newAdmin) external {
        require(msg.sender == admin, "only admin can set new admin");
        address oldAdmin = admin;
        admin = newAdmin;

        emit NewAdmin(oldAdmin, newAdmin);
    }
}
