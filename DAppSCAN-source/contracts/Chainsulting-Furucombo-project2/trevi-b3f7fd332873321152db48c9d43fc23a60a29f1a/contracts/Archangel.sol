// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./interfaces/IArchangel.sol";
import "./interfaces/IFlashLender.sol";
import "./AngelFactory.sol";
import "./FountainFactory.sol";
import "./libraries/Ownable.sol";
import "./libraries/SafeERC20.sol";
import "./utils/ErrorMsg.sol";

/// @title Staking system manager
contract Archangel is Ownable, ErrorMsg {
    using SafeERC20 for IERC20;

    AngelFactory public immutable angelFactory;
    FountainFactory public immutable fountainFactory;
    uint256 public defaultFlashLoanFee = 9;
    uint256 public constant FEE_BASE = 1e4;

    constructor() public {
        angelFactory = new AngelFactory();
        fountainFactory = new FountainFactory();
    }

    // Getters
    /// @notice Return contract name for error message.
    function getContractName() public pure override returns (string memory) {
        return "Archangel";
    }

    /// @notice Get the fountain for given token.
    /// @param token The token to be queried.
    /// @return Fountain address.
    function getFountain(IERC20 token) external view returns (Fountain) {
        return fountainFactory.fountainOf(token);
    }

    /// @notice Fetch the token from fountain or archangel itself. Can
    /// only be called from owner.
    /// @param token The token to be fetched.
    /// @param from The fountain to be fetched.
    /// @return The token amount being fetched.
    function rescueERC20(IERC20 token, Fountain from)
        external
        onlyOwner
        returns (uint256)
    {
        if (fountainFactory.isValid(from)) {
            return from.rescueERC20(token, _msgSender());
        } else {
            uint256 amount = token.balanceOf(address(this));
            token.safeTransfer(_msgSender(), amount);
            return amount;
        }
    }

    /// @notice Set the default fee rate for flash loan. The default fee
    /// rate will be applied when fountain or angel is being created. Can
    /// only be set by owner.

    function setDefaultFlashLoanFee(uint256 fee) external onlyOwner {
        _requireMsg(
            fee <= FEE_BASE,
            "setDefaultFlashLoanFee",
            "fee rate exceeded"
        );
        defaultFlashLoanFee = fee;
    }

    /// @notice Set the flash loan fee rate of angel or fountain. Can only
    /// be set by owner.
    /// @param lender The address of angel of fountain.
    /// @param fee The fee rate to be applied.
    function setFlashLoanFee(address lender, uint256 fee) external onlyOwner {
        IFlashLender(lender).setFlashLoanFee(fee);
    }
}
