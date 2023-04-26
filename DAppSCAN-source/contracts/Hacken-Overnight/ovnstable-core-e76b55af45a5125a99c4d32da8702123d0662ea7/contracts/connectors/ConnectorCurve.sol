// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import "../interfaces/IConnector.sol";
import "./curve/interfaces/iCurvePool.sol";

contract ConnectorCurve is IConnector, Ownable {
    iCurvePool public pool;

    event UpdatedPool(address pool);

    function setPool(address _pool) public onlyOwner {
        require(_pool != address(0), "Zero address not allowed");
        pool = iCurvePool(_pool);
        emit UpdatedPool(_pool);
    }

    function stake(
        address _asset,
        uint256 _amount,
        address _beneficiar
    ) public override {
        uint256[3] memory amounts;
        for (uint256 i = 0; i < 3; i++) {
            address coin = pool.coins(i);
            if (coin == _asset) {
                IERC20(_asset).approve(address(pool), _amount);
                // номер позиции в массиве (amounts) определяет какой актив (_asset) и в каком количестве (_amount)
                // на стороне керва будет застейкано
                amounts[uint256(i)] = _amount;
                uint256 lpTokAmount = pool.calc_token_amount(amounts, true);
                //TODO: процентажи кудато вынести, slippage
                uint256 retAmount = pool.add_liquidity(amounts, (lpTokAmount * 99) / 100, false);
                IERC20(pool.lp_token()).transfer(_beneficiar, retAmount);

                return;
            } else {
                amounts[i] = 0;
            }
        }
        revert("can't find active for staking in pool");
    }

    function unstake(
        address _asset,
        uint256 _amount,
        address _beneficiar
    ) public override returns (uint256) {
        uint256[3] memory amounts;
        for (uint256 i = 0; i < 3; i++) {
            address coin = pool.coins(i);

            if (coin == _asset) {
                amounts[i] = _amount;

                IERC20 lpToken = IERC20(pool.lp_token());
                uint256 onConnectorLpTokenAmount = lpToken.balanceOf(address(this));

                uint256 lpTokAmount = pool.calc_token_amount(amounts, false);
                // _one_coin для возврата конкретной монеты (_assest)
                uint256 withdrawAmount = pool.calc_withdraw_one_coin(lpTokAmount, int128(uint128(i)));
                if (withdrawAmount > onConnectorLpTokenAmount) {
                    revert(string(
                        abi.encodePacked(
                            "Not enough lpToken own ",
                            " _amount: ",
                            Strings.toString(_amount),
                            " lpTok: ",
                            Strings.toString(lpTokAmount),
                            " onConnectorLpTokenAmount: ",
                            Strings.toString(onConnectorLpTokenAmount),
                            " withdrawAmount: ",
                            Strings.toString(withdrawAmount)
                        )
                    ));
                }

                lpToken.approve(address(pool), lpTokAmount);

                //TODO: use withdrawAmount?
                uint256 retAmount = pool.remove_liquidity_one_coin(lpTokAmount, int128(uint128(i)), 0);

                IERC20(_asset).transfer(_beneficiar, retAmount);
                lpToken.transfer(
                    _beneficiar,
                    lpToken.balanceOf(address(this))
                );
                return retAmount;
            } else {
                amounts[i] = 0;
            }
        }
        revert("can't find active for withdraw from pool");
    }


}
