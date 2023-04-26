// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.7;

import "../interfaces/IOracle.sol";

contract MockOracle is IOracle {
    event Update(uint256 _peg);

    ITreasury public treasury;

    uint256 public base = 1 ether;
    uint256 public inBase;
    uint256 public precision = 1 ether;
    uint256 public rate;
    bool public outdated;

    /// @notice Initiate with a fixe change rate
    constructor(
        uint256 rate_,
        uint256 _inDecimals,
        ITreasury _treasury
    ) {
        rate = rate_;
        inBase = 10**_inDecimals;
        treasury = _treasury;
    }

    /// @notice Mock read
    function read() external view override returns (uint256) {
        return rate;
    }

    /// @notice change oracle rate
    function update(uint256 newRate) external {
        rate = newRate;
    }

    function changeInBase(uint256 newInBase) external {
        inBase = newInBase;
    }

    function setTreasury(address _treasury) external override {
        treasury = ITreasury(_treasury);
    }
}
