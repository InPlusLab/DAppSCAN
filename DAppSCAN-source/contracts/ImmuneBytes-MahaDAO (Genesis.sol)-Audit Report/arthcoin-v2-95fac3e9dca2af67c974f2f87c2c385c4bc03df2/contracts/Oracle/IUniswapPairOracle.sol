// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IUniswapPairOracle {
    function update() external;

    function setPeriod(uint256 _period) external;

    function setOwner(address _ownerAddress) external;

    function setTimelock(address _timelockAddress) external;

    function setConsultLeniency(uint256 _consultLeniency) external;

    function setAllowStaleConsults(bool _allowStaleConsults) external;

    function consult(address token, uint256 amountIn)
        external
        view
        returns (uint256 amountOut);

    function canUpdate() external view returns (bool);
}
