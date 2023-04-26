// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.6.9;
pragma experimental ABIEncoderV2;

import { PerpFiOwnableUpgrade } from "./utils/PerpFiOwnableUpgrade.sol";
import {
    ReentrancyGuardUpgradeSafe
} from "@openzeppelin/contracts-ethereum-package/contracts/utils/ReentrancyGuard.sol";
import { IERC20 } from "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/IERC20.sol";
import { Decimal } from "./utils/Decimal.sol";
import { IInsuranceFund } from "./interface/IInsuranceFund.sol";
import { BlockContext } from "./utils/BlockContext.sol";
import { DecimalERC20 } from "./utils/DecimalERC20.sol";
import { IArk } from "./interface/IArk.sol";
import { IAmm } from "./interface/IAmm.sol";

contract InsuranceFund is IInsuranceFund, PerpFiOwnableUpgrade, BlockContext, ReentrancyGuardUpgradeSafe, DecimalERC20 {
    using Decimal for Decimal.decimal;

    //
    // EVENTS
    //

    event Withdrawn(address withdrawer, uint256 amount);
    event TokenAdded(address tokenAddress);
    event TokenRemoved(address tokenAddress);
    event ShutdownAllAmms(uint256 blockNumber);

    //**********************************************************//
    //    The below state variables can not change the order    //
    //**********************************************************//

    mapping(address => bool) private ammMap;
    mapping(address => bool) private quoteTokenMap;
    IAmm[] private amms;
    IERC20[] public quoteTokens;

    // contract dependencies
    IArk public ark;
    address private beneficiary;

    //**********************************************************//
    //    The above state variables can not change the order    //
    //**********************************************************//

    //◥◤◥◤◥◤◥◤◥◤◥◤◥◤◥◤ add state variables below ◥◤◥◤◥◤◥◤◥◤◥◤◥◤◥◤//

    //◢◣◢◣◢◣◢◣◢◣◢◣◢◣◢◣ add state variables above ◢◣◢◣◢◣◢◣◢◣◢◣◢◣◢◣//
    uint256[50] private __gap;

    //
    // FUNCTIONS
    //

    function initialize() external initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
    }

    /**
     * @dev only owner can call
     * @param _amm IAmm address
     */
    function addAmm(IAmm _amm) public onlyOwner {
        require(!isExistedAmm(_amm), "amm already added");
        ammMap[address(_amm)] = true;
        amms.push(_amm);

        // add token if it's new one
        IERC20 token = _amm.quoteAsset();
        if (!isQuoteTokenExisted(token)) {
            quoteTokens.push(token);
            quoteTokenMap[address(token)] = true;
            emit TokenAdded(address(token));
        }
    }

    /**
     * @dev only owner can call. no need to call
     * @param _amm IAmm address
     */
    function removeAmm(IAmm _amm) external onlyOwner {
        require(isExistedAmm(_amm), "amm not existed");
        ammMap[address(_amm)] = false;
        uint256 ammLength = amms.length;
        for (uint256 i = 0; i < ammLength; i++) {
            if (amms[i] == _amm) {
                amms[i] = amms[ammLength - 1];
                amms.pop();
                break;
            }
        }
    }

    /**
     * @notice shutdown all Amms when fatal error happens
     * @dev only owner can call. Emit `ShutdownAllAmms` event
     */
    function shutdownAllAmm() external onlyOwner {
        for (uint256 i; i < amms.length; i++) {
            amms[i].shutdown();
        }
        emit ShutdownAllAmms(block.number);
    }

    function removeToken(IERC20 _token) external onlyOwner {
        require(isQuoteTokenExisted(_token), "token does not exist");

        quoteTokenMap[address(_token)] = false;
        uint256 quoteTokensLength = getQuoteTokenLength();
        for (uint256 i = 0; i < quoteTokensLength; i++) {
            if (quoteTokens[i] == _token) {
                if (i < quoteTokensLength - 1) {
                    quoteTokens[i] = quoteTokens[quoteTokensLength - 1];
                }
                quoteTokens.pop();
                break;
            }
        }

        // transfer all fund to ark
        if (balanceOf(_token).toUint() > 0) {
            _transfer(_token, address(ark), balanceOf(_token));
        }

        emit TokenRemoved(address(_token));
    }

    /**
     * @notice withdraw token to caller
     * @param _amount the amount of quoteToken caller want to withdraw
     */
    function withdraw(IERC20 _quoteToken, Decimal.decimal calldata _amount) external override {
        require(beneficiary == _msgSender(), "caller is not beneficiary");
        require(isQuoteTokenExisted(_quoteToken), "Asset is not supported");

        Decimal.decimal memory quoteBalance = balanceOf(_quoteToken);
        if (_amount.toUint() > quoteBalance.toUint()) {
            Decimal.decimal memory insufficientAmount = _amount.subD(quoteBalance);
            ark.withdrawForLoss(insufficientAmount, _quoteToken);
            quoteBalance = balanceOf(_quoteToken);
        }
        require(quoteBalance.toUint() >= _amount.toUint(), "Fund not enough");

        _transfer(_quoteToken, _msgSender(), _amount);
        emit Withdrawn(_msgSender(), _amount.toUint());
    }

    //
    // SETTER
    //

    function setBeneficiary(address _beneficiary) external onlyOwner {
        beneficiary = _beneficiary;
    }

    function setArk(IArk _ark) public onlyOwner {
        ark = _ark;
    }

    function getQuoteTokenLength() public view returns (uint256) {
        return quoteTokens.length;
    }

    //
    // VIEW
    //
    function isExistedAmm(IAmm _amm) public view override returns (bool) {
        return ammMap[address(_amm)];
    }

    function getAllAmms() external view override returns (IAmm[] memory) {
        return amms;
    }

    function isQuoteTokenExisted(IERC20 _token) internal view returns (bool) {
        return quoteTokenMap[address(_token)];
    }

    function balanceOf(IERC20 _quoteToken) internal view returns (Decimal.decimal memory) {
        return _balanceOf(_quoteToken, address(this));
    }
}
