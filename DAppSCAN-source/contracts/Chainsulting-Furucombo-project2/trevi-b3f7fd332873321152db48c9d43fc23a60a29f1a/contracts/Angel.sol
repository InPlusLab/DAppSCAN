// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./AngelBase.sol";
import "./ERC20FlashLoan.sol";

/// @title Manage the rewards and configuration.
contract Angel is AngelBase, ERC20FlashLoan {
    modifier onlyArchangel() {
        _requireMsg(
            msg.sender == address(archangel),
            "general",
            "not from archangel"
        );
        _;
    }

    constructor(IERC20 token, uint256 flashLoanFee)
        public
        AngelBase(token)
        ERC20FlashLoan(token, flashLoanFee)
    {}

    /// @notice Set the fee rate for flash loan. can only be set by Archangel.
    /// @param fee The fee rate.
    function setFlashLoanFee(uint256 fee) public override onlyArchangel {
        super.setFlashLoanFee(fee);
    }

    /// @notice Set the fee collector. Fee are transferred to Archangel after
    /// flash loan execution.
    function flashLoanFeeCollector() public view override returns (address) {
        return address(archangel);
    }
}
