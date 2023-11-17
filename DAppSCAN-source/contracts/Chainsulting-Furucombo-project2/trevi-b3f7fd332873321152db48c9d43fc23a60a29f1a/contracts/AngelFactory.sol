// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./Angel.sol";
import "./interfaces/IAngelFactory.sol";
import "./utils/ErrorMsg.sol";

/// @title The factory of angel.
contract AngelFactory is ErrorMsg {
    using BoringERC20 for IERC20;
    using BoringMath for uint256;

    IArchangel public immutable archangel;
    mapping(Angel => IERC20) private _rewards;

    event Created(address to);

    constructor() public {
        archangel = IArchangel(msg.sender);
    }

    // Getters
    /// @notice Return contract name for error message.
    function getContractName() public pure override returns (string memory) {
        return "AngelFactory";
    }

    /// @notice Check if angel is valid.
    /// @param angel The angel to be verified.
    /// @return Is valid or not.
    function isValid(Angel angel) external view returns (bool) {
        return (address(_rewards[angel]) != address(0));
    }

    /// @notice Get the reward token of angel.
    /// @param angel The angel address.
    /// @return The reward token address.
    function rewardOf(Angel angel) external view returns (IERC20) {
        return _rewards[angel];
    }

    /// @notice Create the angel of given token as reward. Multiple angels for the
    /// same token is possible.
    function create(IERC20 reward) external returns (Angel) {
        _requireMsg(
            address(reward) != address(0),
            "create",
            "reward is zero address"
        );
        Angel newAngel = new Angel(reward, archangel.defaultFlashLoanFee());
        newAngel.transferOwnership(msg.sender, true, false);
        _rewards[newAngel] = reward;

        emit Created(address(newAngel));

        return newAngel;
    }
}
