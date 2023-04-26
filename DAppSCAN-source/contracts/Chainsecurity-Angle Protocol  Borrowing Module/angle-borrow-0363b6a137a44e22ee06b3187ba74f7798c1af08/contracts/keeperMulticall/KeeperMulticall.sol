// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.12;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./RevertReasonParser.sol";

/// @title KeeperMulticall
/// @notice Allows an authorized caller (keeper) to execute multiple actions in a single tx.
/// @author Angle Core Team
/// @dev Special features:
///         - ability to pay the miner (for private Flashbots transactions)
///         - swap tokens through 1inch
/// @dev Tx need to be encoded as an array of Action. The flag `isDelegateCall` is used for calling functions within this same contract
contract KeeperMulticall is Initializable, AccessControlUpgradeable {
    using SafeERC20 for IERC20;

    bytes32 public constant KEEPER_ROLE = keccak256("KEEPER_ROLE");

    //solhint-disable-next-line
    address private constant _oneInch = 0x1111111254fb6c44bAC0beD2854e76F90643097d;

    struct Action {
        address target;
        bytes data;
        bool isDelegateCall;
    }

    event LogAction(address indexed target, bytes data);
    event SentToMiner(uint256 indexed value);
    event Recovered(address indexed tokenAddress, address indexed to, uint256 amount);

    error AmountOutTooLow(uint256 amount, uint256 min);
    error BalanceTooLow();
    error FlashbotsErrorPayingMiner(uint256 value);
    error IncompatibleLengths();
    error RevertBytes();
    error WrongAmount();
    error ZeroAddress();

    constructor() initializer {}

    function initialize(address keeper) public initializer {
        __AccessControl_init();

        _setupRole(KEEPER_ROLE, keeper);
        _setRoleAdmin(KEEPER_ROLE, KEEPER_ROLE);
    }

    /// @notice Allows an authorized keeper to execute multiple actions in a single step
    /// @param actions Actions to be executed
    /// @param percentageToMiner Percentage to pay to miner expressed in bps (10000)
    /// @dev This is the main entry point for actions to be executed. The `isDelegateCall` flag is used for calling function inside this `KeeperMulticall` contract,
    /// if we call other contracts, the flag should be false
    function executeActions(Action[] memory actions, uint256 percentageToMiner)
        external
        payable
        onlyRole(KEEPER_ROLE)
        returns (bytes[] memory)
    {
        uint256 numberOfActions = actions.length;
        if (numberOfActions == 0) revert IncompatibleLengths();

        bytes[] memory returnValues = new bytes[](numberOfActions + 1);

        uint256 balanceBefore = address(this).balance;

        for (uint256 i = 0; i < numberOfActions; ++i) {
            returnValues[i] = _executeAction(actions[i]);
        }

        if (percentageToMiner > 0) {
            if (percentageToMiner >= 10000) revert WrongAmount();
            uint256 balanceAfter = address(this).balance;
            if (balanceAfter > balanceBefore) {
                uint256 amountToMiner = ((balanceAfter - balanceBefore) * percentageToMiner) / 10000;
                returnValues[numberOfActions] = payFlashbots(amountToMiner);
            }
        }

        return returnValues;
    }

    /// @notice Gets the action address and data and executes it
    /// @param action Action to be executed
    function _executeAction(Action memory action) internal returns (bytes memory) {
        bool success;
        bytes memory response;

        if (action.isDelegateCall) {
            //solhint-disable-next-line
            (success, response) = action.target.delegatecall(action.data);
        } else {
            //solhint-disable-next-line
            (success, response) = action.target.call(action.data);
        }

        require(success, RevertReasonParser.parse(response, "action reverted: "));
        emit LogAction(action.target, action.data);
        return response;
    }

    /// @notice Ability to pay miner directly. Used for Flashbots to execute private transactions
    /// @param value Value to be sent
    function payFlashbots(uint256 value) public payable onlyRole(KEEPER_ROLE) returns (bytes memory) {
        //solhint-disable-next-line
        (bool success, bytes memory response) = block.coinbase.call{ value: value }("");
        if (!success) revert FlashbotsErrorPayingMiner(value);
        emit SentToMiner(value);
        return response;
    }

    /// @notice Used to check the balances the token holds for each token. If we don't have enough of a token, we revert the tx
    /// @param tokens Array of tokens to check
    /// @param minBalances Array of balances for each token
    function finalBalanceCheck(IERC20[] memory tokens, uint256[] memory minBalances) external view returns (bool) {
        uint256 tokensLength = tokens.length;
        if (tokensLength == 0 || tokensLength != minBalances.length) revert IncompatibleLengths();

        for (uint256 i; i < tokensLength; ++i) {
            if (address(tokens[i]) == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE) {
                if (address(this).balance < minBalances[i]) revert BalanceTooLow();
            } else {
                if (tokens[i].balanceOf(address(this)) < minBalances[i]) revert BalanceTooLow();
            }
        }

        return true;
    }

    /// @notice Swap token to another through 1Inch
    /// @param minAmountOut Minimum amount of `out` token to receive for the swap to happen
    /// @param payload Bytes needed for 1Inch API
    function swapToken(uint256 minAmountOut, bytes memory payload) external onlyRole(KEEPER_ROLE) {
        //solhint-disable-next-line
        (bool success, bytes memory result) = _oneInch.call(payload);
        if (!success) _revertBytes(result);

        uint256 amountOut = abi.decode(result, (uint256));
        if (amountOut < minAmountOut) revert AmountOutTooLow(amountOut, minAmountOut);
    }

    /// @notice Copied from 1Inch contract, used to revert if there is an error
    function _revertBytes(bytes memory errMsg) internal pure {
        if (errMsg.length > 0) {
            //solhint-disable-next-line
            assembly {
                revert(add(32, errMsg), mload(errMsg))
            }
        }
        revert RevertBytes();
    }

    /// @notice Approve a `spender` for `token`
    /// @param token Address of the token to approve
    /// @param spender Address of the spender to approve
    /// @param amount Amount to approve
    function approve(
        IERC20 token,
        address spender,
        uint256 amount
    ) external onlyRole(KEEPER_ROLE) {
        uint256 currentAllowance = token.allowance(address(this), spender);
        if (currentAllowance < amount) {
            token.safeIncreaseAllowance(spender, amount - currentAllowance);
        } else if (currentAllowance > amount) {
            token.safeDecreaseAllowance(spender, currentAllowance - amount);
        }
    }

    receive() external payable {}

    /// @notice Withdraw stuck funds
    /// @param token Address of the token to recover
    /// @param receiver Address where to send the tokens
    /// @param amount Amount to recover
    function withdrawStuckFunds(
        address token,
        address receiver,
        uint256 amount
    ) external onlyRole(KEEPER_ROLE) {
        if (receiver == address(0)) revert ZeroAddress();
        if (token == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE) {
            payable(receiver).transfer(amount);
        } else {
            IERC20(token).safeTransfer(receiver, amount);
        }

        emit Recovered(token, receiver, amount);
    }
}
