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

import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import "./interfaces/IQore.sol";
import "./interfaces/IQDistributor.sol";
import "./interfaces/IPriceCalculator.sol";
import "./library/WhitelistUpgradeable.sol";
import { QConstant } from "./library/QConstant.sol";
import "./interfaces/IQToken.sol";

abstract contract QoreAdmin is IQore, WhitelistUpgradeable, ReentrancyGuardUpgradeable {
    /* ========== CONSTANT VARIABLES ========== */

    IPriceCalculator public constant priceCalculator = IPriceCalculator(0x20E5E35ba29dC3B540a1aee781D0814D5c77Bce6);

    /* ========== STATE VARIABLES ========== */

    address public keeper;
    address public override qValidator;
    IQDistributor public qDistributor;

    address[] public markets; // qTokenAddress[]
    mapping(address => QConstant.MarketInfo) public marketInfos; // (qTokenAddress => MarketInfo)

    uint public closeFactor;
    uint public override liquidationIncentive;

    /* ========== Event ========== */

    event MarketListed(address qToken);
    event MarketEntered(address qToken, address account);
    event MarketExited(address qToken, address account);

    event CloseFactorUpdated(uint newCloseFactor);
    event CollateralFactorUpdated(address qToken, uint newCollateralFactor);
    event LiquidationIncentiveUpdated(uint newLiquidationIncentive);
    event BorrowCapUpdated(address indexed qToken, uint newBorrowCap);
    event KeeperUpdated(address newKeeper);
    event QValidatorUpdated(address newQValidator);
    event QDistributorUpdated(address newQDistributor);

    /* ========== MODIFIERS ========== */

    modifier onlyKeeper() {
        require(msg.sender == keeper || msg.sender == owner(), "Qore: caller is not the owner or keeper");
        _;
    }

    modifier onlyListedMarket(address qToken) {
        require(marketInfos[qToken].isListed, "Qore: invalid market");
        _;
    }

    /* ========== INITIALIZER ========== */

    function __Qore_init() internal initializer {
        __WhitelistUpgradeable_init();
        __ReentrancyGuard_init();

        closeFactor = 5e17;
        liquidationIncentive = 11e17;
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function setKeeper(address _keeper) external onlyKeeper {
        require(_keeper != address(0), "Qore: invalid keeper address");
        keeper = _keeper;
        emit KeeperUpdated(_keeper);
    }

    function setQValidator(address _qValidator) external onlyKeeper {
        require(_qValidator != address(0), "Qore: invalid qValidator address");
        qValidator = _qValidator;
        emit QValidatorUpdated(_qValidator);
    }

    function setQDistributor(address _qDistributor) external onlyKeeper {
        require(_qDistributor != address(0), "Qore: invalid qDistributor address");
        qDistributor = IQDistributor(_qDistributor);
        emit QDistributorUpdated(_qDistributor);
    }

    function setCloseFactor(uint newCloseFactor) external onlyKeeper {
        require(
            newCloseFactor >= QConstant.CLOSE_FACTOR_MIN && newCloseFactor <= QConstant.CLOSE_FACTOR_MAX,
            "Qore: invalid close factor"
        );
        closeFactor = newCloseFactor;
        emit CloseFactorUpdated(newCloseFactor);
    }

    function setCollateralFactor(address qToken, uint newCollateralFactor)
        external
        onlyKeeper
        onlyListedMarket(qToken)
    {
        require(newCollateralFactor <= QConstant.COLLATERAL_FACTOR_MAX, "Qore: invalid collateral factor");
        if (newCollateralFactor != 0 && priceCalculator.getUnderlyingPrice(qToken) == 0) {
            revert("Qore: invalid underlying price");
        }

        marketInfos[qToken].collateralFactor = newCollateralFactor;
        emit CollateralFactorUpdated(qToken, newCollateralFactor);
    }

    function setLiquidationIncentive(uint newLiquidationIncentive) external onlyKeeper {
        liquidationIncentive = newLiquidationIncentive;
        emit LiquidationIncentiveUpdated(newLiquidationIncentive);
    }

    function setMarketBorrowCaps(address[] calldata qTokens, uint[] calldata newBorrowCaps) external onlyKeeper {
        require(qTokens.length != 0 && qTokens.length == newBorrowCaps.length, "Qore: invalid data");

        for (uint i = 0; i < qTokens.length; i++) {
            marketInfos[qTokens[i]].borrowCap = newBorrowCaps[i];
            emit BorrowCapUpdated(qTokens[i], newBorrowCaps[i]);
        }
    }

    function listMarket(
        address payable qToken,
        uint borrowCap,
        uint collateralFactor
    ) external onlyKeeper {
        require(!marketInfos[qToken].isListed, "Qore: already listed market");
        for (uint i = 0; i < markets.length; i++) {
            require(markets[i] != qToken, "Qore: already listed market");
        }

        marketInfos[qToken] = QConstant.MarketInfo({
            isListed: true,
            borrowCap: borrowCap,
            collateralFactor: collateralFactor
        });
        markets.push(qToken);
        emit MarketListed(qToken);
    }

    function removeMarket(address payable qToken) external onlyKeeper {
        require(marketInfos[qToken].isListed, "Qore: unlisted market");
        require(IQToken(qToken).totalSupply() == 0 && IQToken(qToken).totalBorrow() == 0, "Qore: cannot remove market");

        uint length = markets.length;
        for (uint i = 0; i < length; i++) {
            if (markets[i] == qToken) {
                markets[i] = markets[length - 1];
                markets.pop();
                delete marketInfos[qToken];
                break;
            }
        }
    }
}
