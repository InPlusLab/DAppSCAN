// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "../base/BasePool.sol";

contract TestBasePool is BasePool {

    constructor(
        string memory _name,
        string memory _symbol,
        address _depositToken,
        address _rewardToken,
        address _escrowPool,
        uint256 _escrowPortion,
        uint256 _escrowDuration
    ) BasePool(_name, _symbol, _depositToken, _rewardToken, _escrowPool, _escrowPortion, _escrowDuration) {
        // silence
    }
    function mint(address _receiver, uint256 _amount) external {
        _mint(_receiver, _amount);
    }

    function burn(address _from, uint256 _amount) external {
        _burn(_from, _amount);
    }
}