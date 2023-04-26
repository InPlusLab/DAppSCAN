// SPDX-License-Identifier: MIT
pragma solidity ^0.6.6;

import {ILimaSwap, IERC20} from "../interfaces/ILimaSwap.sol";
import {FakeInvestmentToken} from "./FakeInvestmentToken.sol";

import {
    Initializable
} from "@openzeppelin/contracts-ethereum-package/contracts/Initializable.sol";

contract FakeLimaSwap is ILimaSwap, Initializable {
    address public unwrappedToken;
    address public gov;

    function initialize(address _unwrappedToken, address _gov) public initializer {
        unwrappedToken = _unwrappedToken;
        gov = _gov;

    }

    function getGovernanceToken(address token) external override view returns (address) {
        return gov;
    }

    function getExpectedReturn(
        address,
        address,
        uint256 amount
    ) external override view returns (uint256 returnAmount) {
        returnAmount = amount * 2;
    }

    function swap(
        address,
        address fromToken,
        address toToken,
        uint256 amount,
        uint256 minimumReturnAmount
    ) external override returns (uint256 returnAmount) {
        returnAmount = amount * 2;
        FakeInvestmentToken(fromToken).burn(msg.sender, amount);
        require(
            returnAmount >= minimumReturnAmount,
            "the return amount needs to bigger then the minimum"
        );
        FakeInvestmentToken(toToken).mint(msg.sender, returnAmount);
    }

    function unwrap(
        address interestBearingToken,
        uint256 amount,
        address recipient
    ) external override {
        FakeInvestmentToken(interestBearingToken).burn(msg.sender, amount);

        FakeInvestmentToken(unwrappedToken).mint(recipient, amount);
    }
}
