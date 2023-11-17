// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./libraries/boringcrypto/BoringBatchable.sol";
import "./HarvestPermit.sol";
import "./JoinPermit.sol";
import "./ERC20FlashLoan.sol";

/// @title The fountain
contract Fountain is
    HarvestPermit,
    JoinPermit,
    ERC20FlashLoan,
    BoringBatchable
{
    modifier onlyArchangel {
        _requireMsg(
            _msgSender() == address(archangel),
            "general",
            "not from archangel"
        );
        _;
    }

    constructor(
        IERC20 token,
        string memory name_,
        string memory symbol_,
        uint256 flashLoanFee
    )
        public
        FountainToken(name_, symbol_)
        FountainBase(token)
        ERC20FlashLoan(token, flashLoanFee)
    {}

    /// @notice Fetch the token from fountain. Can only be called by Archangel.
    /// Will only fetch the extra part if the token is the staking token. Otherwise
    /// the entire balance will be fetched.
    /// @param token The token address.
    /// @param to The receiver.
    /// @return The transferred amount.
    function rescueERC20(IERC20 token, address to)
        external
        onlyArchangel
        returns (uint256)
    {
        uint256 amount;
        if (token == stakingToken) {
            amount = token.balanceOf(address(this)).sub(totalSupply());
        } else {
            amount = token.balanceOf(address(this));
        }
        token.safeTransfer(to, amount);

        return amount;
    }

    /// @notice Set the fee rate for flash loan. can only be set by Archangel.
    /// @param fee The fee rate.
    function setFlashLoanFee(uint256 fee) public override onlyArchangel {
        super.setFlashLoanFee(fee);
    }
}
