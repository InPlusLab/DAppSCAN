pragma solidity 0.5.16;
pragma experimental ABIEncoderV2;
import "openzeppelin-solidity-2.3.0/contracts/ownership/Ownable.sol";
import "openzeppelin-solidity-2.3.0/contracts/math/SafeMath.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "./GoblinConfig.sol";
import "./PriceOracle.sol";
import "./SafeToken.sol";

interface IMasterChefGoblin {
    function lpToken() external view returns (IUniswapV2Pair);
}

contract MasterChefGoblinConfig is Ownable, GoblinConfig {
    using SafeToken for address;
    using SafeMath for uint256;

    struct Config {
        bool acceptDebt;
        uint64 workFactor;
        uint64 killFactor;
        uint64 maxPriceDiff;
    }

    PriceOracle public oracle;
    mapping (address => Config) public goblins;

    constructor(PriceOracle _oracle) public {
        oracle = _oracle;
    }

    /// @dev Set oracle address. Must be called by owner.
    function setOracle(PriceOracle _oracle) external onlyOwner {
        oracle = _oracle;
    }

    /// @dev Set goblin configurations. Must be called by owner.
    function setConfigs(address[] calldata addrs, Config[] calldata configs) external onlyOwner {
        uint256 len = addrs.length;
        require(configs.length == len, "bad len");
        for (uint256 idx = 0; idx < len; idx++) {
            goblins[addrs[idx]] = Config({
                acceptDebt: configs[idx].acceptDebt,
                workFactor: configs[idx].workFactor,
                killFactor: configs[idx].killFactor,
                maxPriceDiff: configs[idx].maxPriceDiff
            });
        }
    }

    /// @dev Return whether the given goblin is stable, presumably not under manipulation.
    function isStable(address goblin) public view returns (bool) {
        IUniswapV2Pair lp = IMasterChefGoblin(goblin).lpToken();
        address token0 = lp.token0();
        address token1 = lp.token1();
        // 1. Check that reserves and balances are consistent (within 1%)
        (uint256 r0, uint256 r1,) = lp.getReserves();
        uint256 t0bal = token0.balanceOf(address(lp));
        uint256 t1bal = token1.balanceOf(address(lp));
        require(t0bal.mul(100) <= r0.mul(101), "bad t0 balance");
        require(t1bal.mul(100) <= r1.mul(101), "bad t1 balance");
        // 2. Check that price is in the acceptable range
        (uint256 price, uint256 lastUpdate) = oracle.getPrice(token0, token1);
        require(lastUpdate >= now - 7 days, "price too stale");
        uint256 lpPrice = r1.mul(1e18).div(r0);
        uint256 maxPriceDiff = goblins[goblin].maxPriceDiff;
        //SWC-101-Integer Overflow and Underflow: L68-L69
        require(lpPrice <= price.mul(maxPriceDiff).div(10000), "price too high");
        require(lpPrice >= price.mul(10000).div(maxPriceDiff), "price too low");
        // 3. Done
        return true;
    }

    /// @dev Return whether the given goblin accepts more debt.
    function acceptDebt(address goblin) external view returns (bool) {
        require(isStable(goblin), "!stable");
        return goblins[goblin].acceptDebt;
    }

    /// @dev Return the work factor for the goblin + ETH debt, using 1e4 as denom.
    function workFactor(address goblin, uint256 /* debt */) external view returns (uint256) {
        require(isStable(goblin), "!stable");
        return uint256(goblins[goblin].workFactor);
    }

    /// @dev Return the kill factor for the goblin + ETH debt, using 1e4 as denom.
    function killFactor(address goblin, uint256 /* debt */) external view returns (uint256) {
        require(isStable(goblin), "!stable");
        return uint256(goblins[goblin].killFactor);
    }
}
