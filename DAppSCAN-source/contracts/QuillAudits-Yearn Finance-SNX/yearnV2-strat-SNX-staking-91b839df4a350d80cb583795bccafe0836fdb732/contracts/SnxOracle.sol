// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import {
    SafeERC20,
    SafeMath,
    IERC20,
    Address
} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/Math.sol";

interface IER {
    function updateRates(
        bytes32[] calldata currencyKeys,
        uint256[] calldata newRates,
        uint256 timeSent
    ) external returns (bool);
}

interface ISynthetix {
    function availableCurrencyKeys() external view returns (bytes32[] memory);

    function availableSynthCount() external view returns (uint256);
}

contract SnxOracle {
    IER public exchangeRate;
    ISynthetix public synthetix;

    constructor(address _exchangeRates) public {
        exchangeRate = IER(_exchangeRates);
        //synthetix = ISynthetix(_synthetix);
    }

    function updateAllPrices() external {
        uint256 _count = synthetix.availableSynthCount();
        bytes32[] memory keys = synthetix.availableCurrencyKeys();
    }

    function updateSnxPrice(uint256 _price) external {
        bytes32[] memory keys = new bytes32[](1);
        keys[0] = "SNX";
        uint256[] memory rates = new uint256[](1);
        rates[0] = _price;
        exchangeRate.updateRates(keys, rates, now);
    }

    function updateBTCPrice(uint256 _price) external {
        bytes32[] memory keys = new bytes32[](1);
        keys[0] = "sBTC";
        uint256[] memory rates = new uint256[](1);
        rates[0] = _price;
        exchangeRate.updateRates(keys, rates, now);
    }

    function updateETHPrice(uint256 _price) external {
        bytes32[] memory keys = new bytes32[](1);
        keys[0] = "sETH";
        uint256[] memory rates = new uint256[](1);
        rates[0] = _price;
        exchangeRate.updateRates(keys, rates, now);
    }
}
