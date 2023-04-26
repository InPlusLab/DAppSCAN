// SPDX-License-Identifier: MIT
pragma experimental ABIEncoderV2;
pragma solidity ^0.7.1;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "../interfaces/ISynthetix.sol";
import "./MockToken.sol";

contract MockSynthetix is ISynthetix {
    using SafeMath for uint256;

    mapping(bytes32=>MockToken) public keyToToken;
    mapping(bytes32=>uint256) public tokenPrice;

    // Mock variables to create edge cases
    uint256 public subtractSourceAmount;
    uint256 public subtractOutputAmount;

    function setSubtractSourceAmount(uint256 _amount) external {
        subtractSourceAmount = _amount;
    }

    function setSubtractOutputAmount(uint256 _amount) external {
        subtractOutputAmount = _amount;
    }

    function exchange(bytes32 _sourceCurrencyKey, uint256 _sourceAmount, bytes32 _destinationCurrencyKey) external override {
        uint256 sourcePrice = tokenPrice[_sourceCurrencyKey];
        uint256 destinationPrice = tokenPrice[_destinationCurrencyKey];
        uint256 outputAmount = _sourceAmount.mul(sourcePrice).div(destinationPrice);

        getOrSetToken(_sourceCurrencyKey).burn(_sourceAmount.sub(subtractSourceAmount), msg.sender);
        getOrSetToken(_destinationCurrencyKey).mint(outputAmount.sub(subtractOutputAmount), msg.sender);
    }

    function getOrSetToken(bytes32 _currencyKey) public returns(MockToken) {
        if(address(keyToToken[_currencyKey]) == address(0)) {
            keyToToken[_currencyKey] = new MockToken(string(abi.encode(_currencyKey)), string(abi.encode(_currencyKey)));
            tokenPrice[_currencyKey] = 1 ether;
        }

        return keyToToken[_currencyKey];
    }

    function setPrice(bytes32 _currencyKey, uint256 _price) external {
        tokenPrice[_currencyKey] = _price;
    }

    function getToken(bytes32 _currencyKey) external view returns(address) {
        return address(keyToToken[_currencyKey]);
    }
}