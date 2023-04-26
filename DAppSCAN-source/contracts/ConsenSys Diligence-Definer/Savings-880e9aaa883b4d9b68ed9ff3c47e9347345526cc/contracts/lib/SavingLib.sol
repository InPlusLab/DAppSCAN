pragma solidity 0.5.14;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "../config/GlobalConfig.sol";
import "openzeppelin-solidity/contracts/token/ERC20/SafeERC20.sol";
import "./Utils.sol";
import { ICToken } from "../compound/ICompound.sol";
import { ICETH } from "../compound/ICompound.sol";
// import "@nomiclabs/buidler/console.sol";

library SavingLib {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    /**
     * Receive the amount of token from msg.sender
     * @param _amount amount of token
     * @param _token token address
     */
    function receive(GlobalConfig globalConfig, uint256 _amount, address _token) public {
        if (Utils._isETH(address(globalConfig), _token)) {
            require(msg.value == _amount, "The amount is not sent from address.");
        } else {
            //When only tokens received, msg.value must be 0
            require(msg.value == 0, "msg.value must be 0 when receiving tokens");
            IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
        }
    }

    /**
     * Send the amount of token to an address
     * @param _amount amount of token
     * @param _token token address
     */
    function send(GlobalConfig globalConfig, uint256 _amount, address _token) public {
        if (Utils._isETH(address(globalConfig), _token)) {
            msg.sender.transfer(_amount);
        } else {
            IERC20(_token).safeTransfer(msg.sender, _amount);
        }
    }

    // ============================================
    // EMERGENCY WITHDRAWAL FUNCTIONS
    // Needs to be removed when final version deployed
    // ============================================
    function emergencyWithdraw(GlobalConfig globalConfig, address _token) public {
        address cToken = globalConfig.tokenInfoRegistry().getCToken(_token);
        if(Utils._isETH(address(globalConfig), _token)) {
            // uint256 success = ICToken(cToken).redeem(ICToken(cToken).balanceOf(address(this)));
            require(ICToken(cToken).redeem(ICToken(cToken).balanceOf(address(this))) == 0, "redeem ETH failed");
            globalConfig.constants().EMERGENCY_ADDR().transfer(address(this).balance);
        } else {
            // uint256 success = ICToken(cToken).redeem(ICToken(cToken).balanceOf(address(this)));
            if(cToken != address(0)) {
                require(ICToken(cToken).redeem(ICToken(cToken).balanceOf(address(this))) == 0, "redeem Token failed");
            }
            // uint256 amount = IERC20(_token).balanceOf(address(this));
            require(IERC20(_token).transfer(globalConfig.constants().EMERGENCY_ADDR(), IERC20(_token).balanceOf(address(this))), "transfer failed");
        }
    }

}