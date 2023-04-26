// SPDX-License-Identifier: MIT
/// @dev size: 2.622 Kbytes
pragma solidity ^0.8.0;

import "./LossProvisionInterface.sol";
import "../security/Ownable.sol";
import "../Controller/ControllerInterface.sol";
import { IERC20 } from "../ERC20/IERC20.sol";

contract LossProvisionPool is LossProvisionInterface, Ownable {

    ControllerInterface public controller;

    uint256 public lossProvisionFee = 1e16;
    uint256 public buyBackProvisionFee = 1.5e16;

    event FeesChanged(uint256 indexed lossProvisionFee, uint256 indexed buyBackProvisionFee);

    constructor(ControllerInterface _controller) {
        controller = _controller;
    }

    /**
     * @dev See {LossProvisionInterface-getFeesPercent}.
     */
    function getFeesPercent() external override view returns (uint256) {
        return lossProvisionFee + buyBackProvisionFee;
    }

    function balanceOf(address stableCoin) public view returns (uint256) {
        require(controller.containsStableCoin(stableCoin), "StableCoin not supported");
        return IERC20(stableCoin).balanceOf(address(this));
    }

    function balanceOfAMPT() public view returns (uint256) {
        IERC20 amptToken = controller.amptToken();
        return amptToken.balanceOf(address(this));
    }

    function transfer(address stableCoin, address to) external onlyOwner {
        require(controller.containsStableCoin(stableCoin), "StableCoin not supported");
        assert(IERC20(stableCoin).transfer(to, balanceOf(stableCoin)));
    }

    function transferAMPT(address to) external onlyOwner {
        IERC20 amptToken = controller.amptToken();
        assert(amptToken.transfer(to, amptToken.balanceOf(address(this))));
    }

    function updateFees(uint256 _lossProvisionFee, uint256 _buyBackProvisionFee) external onlyOwner {
        lossProvisionFee = _lossProvisionFee;
        buyBackProvisionFee = _buyBackProvisionFee;

        emit FeesChanged(lossProvisionFee, buyBackProvisionFee);
    }
}