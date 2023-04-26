// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

/*
      ___       ___       ___       ___       ___
     /\  \     /\__\     /\  \     /\  \     /\  \
    /::\  \   /:/ _/_   /::\  \   _\:\  \    \:\  \
    \:\:\__\ /:/_/\__\ /::\:\__\ /\/::\__\   /::\__\
     \::/  / \:\/:/  / \:\::/  / \::/\/__/  /:/\/__/
     /:/  /   \::/  /   \::/  /   \:\__\    \/__/
     \/__/     \/__/     \/__/     \/__/

*
* MIT License
* ===========
*
* Copyright (c) 2021 QubitFinance
*
* Permission is hereby granted, free of charge, to any person obtaining a copy
* of this software and associated documentation files (the "Software"), to deal
* in the Software without restriction, including without limitation the rights
* to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
* copies of the Software, and to permit persons to whom the Software is
* furnished to do so, subject to the following conditions:
*
* The above copyright notice and this permission notice shall be included in all
* copies or substantial portions of the Software.
*
* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
* IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
* FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
* AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
* LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
* OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
* SOFTWARE.
*/

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/IBEP20.sol";

import "../interfaces/AggregatorV3Interface.sol";
import "../interfaces/IPriceCalculator.sol";
import "../interfaces/IQToken.sol";
import "../interfaces/IPancakePair.sol";
import "../interfaces/IPancakeFactory.sol";
import "../library/HomoraMath.sol";

contract PriceCalculatorBSC is IPriceCalculator, OwnableUpgradeable {
    using SafeMath for uint;
    using HomoraMath for uint;

    address public constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;

    IPancakeFactory private constant factory = IPancakeFactory(0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73);

    /* ========== STATE VARIABLES ========== */

    address public keeper;
    mapping(address => ReferenceData) public references;
    mapping(address => address) private tokenFeeds;

    /* ========== Event ========== */

    event MarketListed(address qToken);
    event MarketEntered(address qToken, address account);
    event MarketExited(address qToken, address account);

    event CloseFactorUpdated(uint newCloseFactor);
    event CollateralFactorUpdated(address qToken, uint newCollateralFactor);
    event LiquidationIncentiveUpdated(uint newLiquidationIncentive);
    event BorrowCapUpdated(address indexed qToken, uint newBorrowCap);

    /* ========== MODIFIERS ========== */

    modifier onlyKeeper() {
        require(msg.sender == keeper || msg.sender == owner(), "Qore: caller is not the owner or keeper");
        _;
    }

    /* ========== INITIALIZER ========== */

    function initialize() external initializer {
        __Ownable_init();
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function setKeeper(address _keeper) external onlyKeeper {
        require(_keeper != address(0), "PriceCalculatorBSC: invalid keeper address");
        keeper = _keeper;
    }

    function setTokenFeed(address asset, address feed) external onlyKeeper {
        tokenFeeds[asset] = feed;
    }

    function setPrices(address[] memory assets, uint[] memory prices) external onlyKeeper {
        for (uint i = 0; i < assets.length; i++) {
            references[assets[i]] = ReferenceData({lastData : prices[i], lastUpdated : block.timestamp});
        }
    }

    /* ========== VIEWS ========== */

    function priceOf(address asset) public view override returns (uint priceInUSD) {
        uint assetDecimals = asset == address(0) ? 1e18 : 10 ** uint(IBEP20(asset).decimals());
        (, priceInUSD) = _oracleValueOf(asset, assetDecimals);
        return priceInUSD;
    }

    function pricesOf(address[] memory assets) public view override returns (uint[] memory) {
        uint[] memory prices = new uint[](assets.length);
        for (uint i = 0; i < assets.length; i++) {
            prices[i] = priceOf(assets[i]);
        }
        return prices;
    }

    function getUnderlyingPrice(address qToken) public view override returns (uint) {
        return priceOf(IQToken(qToken).underlying());
    }

    function getUnderlyingPrices(address[] memory qTokens) public view override returns (uint[] memory) {
        uint[] memory prices = new uint[](qTokens.length);
        for (uint i = 0; i < qTokens.length; i++) {
            prices[i] = priceOf(IQToken(qTokens[i]).underlying());
        }
        return prices;
    }

    function priceOfBNB() public view returns (uint) {
        (, int price, , ,) = AggregatorV3Interface(tokenFeeds[WBNB]).latestRoundData();
        return uint(price).mul(1e10);
    }

    function valueOfAsset(address asset, uint amount) public view override returns (uint valueInBNB, uint valueInUSD) {
        if (asset == address(0) || asset == WBNB) {
            return _oracleValueOf(asset, amount);
        } else if (keccak256(abi.encodePacked(IPancakePair(asset).symbol())) == keccak256("Cake-LP")) {
            return _getPairPrice(asset, amount);
        } else {
            return _oracleValueOf(asset, amount);
        }
    }

    function unsafeValueOfAsset(address asset, uint amount) public view returns (uint valueInBNB, uint valueInUSD) {
        valueInBNB = 0;
        valueInUSD = 0;

        if (asset == address(0) || asset == WBNB) {
            valueInBNB = amount;
            valueInUSD = amount.mul(priceOfBNB()).div(1e18);
        } else if (keccak256(abi.encodePacked(IPancakePair(asset).symbol())) == keccak256("Cake-LP")) {
            if (IPancakePair(asset).totalSupply() == 0) return (0, 0);

            (uint reserve0, uint reserve1,) = IPancakePair(asset).getReserves();
            if (IPancakePair(asset).token0() == WBNB) {
                valueInBNB = amount.mul(reserve0).mul(2).div(IPancakePair(asset).totalSupply());
                valueInUSD = valueInBNB.mul(priceOfBNB()).div(1e18);
            } else if (IPancakePair(asset).token1() == WBNB) {
                valueInBNB = amount.mul(reserve1).mul(2).div(IPancakePair(asset).totalSupply());
                valueInUSD = valueInBNB.mul(priceOfBNB()).div(1e18);
            } else {
                (uint tokenPriceInBNB,) = valueOfAsset(IPancakePair(asset).token0(), 10 ** uint(IBEP20(IPancakePair(asset).token0()).decimals()));
                if (tokenPriceInBNB == 0) {
                    (tokenPriceInBNB,) = valueOfAsset(IPancakePair(asset).token1(), 10 ** uint(IBEP20(IPancakePair(asset).token1()).decimals()));
                    if (IBEP20(IPancakePair(asset).token1()).decimals() < uint8(18)) {
                        reserve1 = reserve1.mul(10 ** uint(uint8(18) - IBEP20(IPancakePair(asset).token1()).decimals()));
                    }
                    valueInBNB = amount.mul(reserve1).mul(2).mul(tokenPriceInBNB).div(1e18).div(IPancakePair(asset).totalSupply());
                } else {
                    if (IBEP20(IPancakePair(asset).token0()).decimals() < uint8(18)) {
                        reserve0 = reserve0.mul(10 ** uint(uint8(18) - IBEP20(IPancakePair(asset).token0()).decimals()));
                    }
                    valueInBNB = amount.mul(reserve0).mul(2).mul(tokenPriceInBNB).div(1e18).div(IPancakePair(asset).totalSupply());
                }
                valueInUSD = valueInBNB.mul(priceOfBNB()).div(1e18);
            }
        } else {
            address pair = factory.getPair(asset, WBNB);
            if (IBEP20(asset).balanceOf(pair) == 0) return (0, 0);
            (uint reserve0, uint reserve1,) = IPancakePair(pair).getReserves();

            if (IPancakePair(pair).token0() == WBNB) {
                valueInBNB = reserve0.mul(amount).div(reserve1);
            } else if (IPancakePair(pair).token1() == WBNB) {
                valueInBNB = reserve1.mul(amount).div(reserve0);
            } else {
                return (0, 0);
            }
            valueInUSD = valueInBNB.mul(priceOfBNB()).div(1e18);
        }
    }

    /* ========== PRIVATE FUNCTIONS ========== */

    function _getPairPrice(address pair, uint amount) private view returns (uint valueInBNB, uint valueInUSD) {
        address token0 = IPancakePair(pair).token0();
        address token1 = IPancakePair(pair).token1();
        uint totalSupply = IPancakePair(pair).totalSupply();
        (uint reserve0, uint reserve1,) = IPancakePair(pair).getReserves();

        if (IBEP20(token0).decimals() < uint8(18)) {
            reserve0 = reserve0.mul(10 ** uint(uint8(18) - IBEP20(token0).decimals()));
        }

        if (IBEP20(token1).decimals() < uint8(18)) {
            reserve1 = reserve1.mul(10 ** uint(uint8(18) - IBEP20(token1).decimals()));
        }

        uint sqrtK = HomoraMath.sqrt(reserve0.mul(reserve1)).fdiv(totalSupply);
        (uint px0,) = _oracleValueOf(token0, 10 ** uint(IBEP20(token0).decimals()));
        (uint px1,) = _oracleValueOf(token1, 10 ** uint(IBEP20(token1).decimals()));
        uint fairPriceInBNB = sqrtK.mul(2).mul(HomoraMath.sqrt(px0)).div(2 ** 56).mul(HomoraMath.sqrt(px1)).div(2 ** 56);

        valueInBNB = fairPriceInBNB.mul(amount).div(1e18);
        valueInUSD = valueInBNB.mul(priceOfBNB()).div(1e18);
    }

    function _oracleValueOf(address asset, uint amount) private view returns (uint valueInBNB, uint valueInUSD) {
        valueInUSD = 0;
        uint assetDecimals = asset == address(0) ? 1e18 : 10 ** uint(IBEP20(asset).decimals());
        if (tokenFeeds[asset] != address(0)) {
            (, int price, , ,) = AggregatorV3Interface(tokenFeeds[asset]).latestRoundData();
            valueInUSD = uint(price).mul(1e10).mul(amount).div(assetDecimals);
        } else if (references[asset].lastUpdated > block.timestamp.sub(1 days)) {
            valueInUSD = references[asset].lastData.mul(amount).div(assetDecimals);
        }
        valueInBNB = valueInUSD.mul(1e18).div(priceOfBNB());
    }
}
