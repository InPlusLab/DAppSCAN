pragma solidity 0.5.16;
import "openzeppelin-solidity-2.3.0/contracts/ownership/Ownable.sol";
import "./PriceOracle.sol";

contract SimplePriceOracle is Ownable, PriceOracle {
    event PriceUpdate(address indexed token0, address indexed token1, uint256 price);

    struct PriceData {
        uint192 price;
        uint64 lastUpdate;
    }

    /// @notice Public price data mapping storage.
    mapping (address => mapping (address => PriceData)) public store;

    /// @dev Set the prices of the token token pairs. Must be called by the owner.
    function setPrices(
        address[] calldata token0s,
        address[] calldata token1s,
        uint256[] calldata prices
    )
        external
        onlyOwner
    {
        uint256 len = token0s.length;
        require(token1s.length == len, "bad token1s length");
        require(prices.length == len, "bad prices length");
        for (uint256 idx = 0; idx < len; idx++) {
            address token0 = token0s[idx];
            address token1 = token1s[idx];
            uint256 price = prices[idx];
            store[token0][token1] = PriceData({
                price: uint192(price),
                lastUpdate: uint64(now)
            });
            emit PriceUpdate(token0, token1, price);
        }
    }

    /// @dev Return the wad price of token0/token1, multiplied by 1e18
    /// NOTE: (if you have 1 token0 how much you can sell it for token1)
    function getPrice(address token0, address token1)
        external view
        returns (uint256 price, uint256 lastUpdate)
    {
        PriceData memory data = store[token0][token1];
        price = uint256(data.price);
        lastUpdate = uint256(data.lastUpdate);
        require(price != 0 && lastUpdate != 0, "bad price data");
        return (price, lastUpdate);
    }
}
