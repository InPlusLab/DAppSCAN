// SPDX-License-Identifier: MIT
pragma solidity ^0.6.7;

import "../strategy-basis-farm-base.sol";
import "../../lib/erc20.sol";

contract StrategyBasisBacDaiLp is StrategyBasisFarmBase {

    constructor(
        address _rewards_token,
        address _pool,
        address _controller,
        address _token1,
        address _token2,
        address[] memory _path,
        address _lptoken,
        address _strategist,
        uint256 _poolId        
    )
        public
        StrategyBasisFarmBase(
            _rewards_token,
            _pool,
            _controller,
            _token1,
            _token2,
            _path,
            _lptoken,
            _strategist,
            _poolId
        )
    {}

    // **** Views ****

    function getName() external override pure returns (string memory) {
        return "StrategyBasisBacDaiLp";
    }
}
