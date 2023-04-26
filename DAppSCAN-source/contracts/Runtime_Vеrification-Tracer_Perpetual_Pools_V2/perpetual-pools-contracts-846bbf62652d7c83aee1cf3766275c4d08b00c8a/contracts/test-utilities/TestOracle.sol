// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

/// @title A mockup oracle wrapper. Don't use for production.
contract TestOracle {
    int256 internal price;
    address public oracle;

    function setOracle(address _oracle) external {
        require(oracle != address(0), "Oracle cannot be 0 address");
        oracle = _oracle;
    }

    function incrementPrice() external {
        price += 1;
    }

    function getPrice() external view returns (int256) {
        return price;
    }
}
