// SPDX-License-Identifier: https://github.com/lendroidproject/protocol.2.0/blob/master/LICENSE.md
pragma solidity 0.7.4;

import "./BasePool.sol";


/** @title UNIV2SHRIMPPool
    @author Lendroid Foundation
    @notice Inherits the BasePool contract, and contains reward distribution
        logic for the $HRIMP token.
    @dev Audit certificate : Pending
*/


contract UNIV2SHRIMPPool is BasePool {

    using SafeMath for uint256;

    uint256 public constant HALFLIFE = 7257600;// 84 days

    /**
        @notice Registers the Pool name as “UNIV2SHRIMPPool” as Pool name,
                LST-WETH-UNIV2 as the LP Token, and
                $HRIMP as the Reward Token.
        @param rewardTokenAddress : $HRIMP Token address
        @param lpTokenAddress : LST-WETH-UNIV2 Token address
    */
    constructor(address rewardTokenAddress, address lpTokenAddress)
        BasePool("UNIV2SHRIMPPool", rewardTokenAddress, lpTokenAddress) {
    }

    /**
        @notice Displays total $HRIMP rewards available for a given epoch.
        @dev Series 0 :
                Epochs : 0
                Total $HRIMP distributed : 2.4 M
                Distribution duration : None
            Series 1 :
                Epochs : 1-84
                Total $HRIMP distributed : 12 M
                Distribution duration : 28 days
            Series 2 :
                Epochs : 85-336
                Total $HRIMP distributed : 21.6 M
                Distribution duration : 84 days
            Series 3 :
                Epochs : 337-588
                Total $HRIMP distributed : 10.8 M
                Distribution duration : 84 days
            Series 4 :
                Epochs : 589-840
                Total $HRIMP distributed : 5.4 M
                Distribution duration : 84 days
            Series 5 :
                Epochs : 841-1092
                Total $HRIMP distributed : 2.7 M
                Distribution duration : 84 days
            Series 6 :
                Epochs : 1093+
                Total $HRIMP distributed : 1.35 M
                Distribution duration : 84 days
        @param epoch : 8-hour window number
        @return totalRewards in $HRIMP Tokens distributed during the given epoch
    */
    function totalRewardsInEpoch(uint256 epoch) override pure public returns (uint256 totalRewards) {
        if (epoch == 0) {
            totalRewards = 2400000 * (10 ** 18);// 2.4 M
        }
        else if (epoch > 0 && epoch <= 84) {
            totalRewards = 12000000 * (10 ** 18);// 12 M
        }
        else if (epoch > 84 && epoch <= 336) {
            totalRewards = 41850000 * (10 ** 18);// 21.6 M
        }
        else if (epoch > 336 && epoch <= 588) {
            totalRewards = 10800000 * (10 ** 18);// 10.8 M
        }
        else if (epoch > 588 && epoch <= 840) {
            totalRewards = 5400000 * (10 ** 18);// 5.4 M
        }
        else if (epoch > 840 && epoch <= 1092) {
            totalRewards = 2700000 * (10 ** 18);// 2.7 M
        }
        else {
            totalRewards = 1350000 * (10 ** 18);// 1.35 M
        }

        return (epoch == 0) ?
          totalRewards :
          (epoch > 0 && epoch <= 84) ?
          totalRewards.div(HALFLIFE.mul(3)) :
          totalRewards.div(HALFLIFE.mul(9));
    }

}
