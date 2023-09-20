// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "../utils/OwnablePausable.sol";
import "../uniswap/IUniswapV2Router02.sol";

contract ProfitSplitter is OwnablePausable {
    using SafeMath for uint256;
    using SafeERC20 for ERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    uint256 public constant SHARE_ACCURACY = 6;

    uint256 public constant SHARE_DIGITS = 2;

    /// @notice Incoming token.
    ERC20 public incoming;

    /// @notice Budget contract address.
    address payable public budget;

    /// @notice Target budget ETH balance.
    uint256 public budgetBalance;

    /// @notice Recipients share.
    mapping(address => uint256) public shares;

    /// @dev Recipients addresses index.
    EnumerableSet.AddressSet private recipientsIndex;

    /// @notice Uniswap router contract address.
    IUniswapV2Router02 public uniswapRouter;

    /// @notice An event thats emitted when an incoming token transferred to recipient.
    event Transfer(address recipient, uint256 amount);

    /// @notice An event thats emitted when an budget contract address and target balance changed.
    event BudgetChanged(address newBudget, uint256 newBalance);

    /// @notice An event thats emitted when an incoming token changed.
    event IncomingChanged(address newIncoming);

    /// @notice An event thats emitted when an uniswap router contract address changed.
    event UniswapRouterChanged(address newUniswapRouter);

    /// @notice An event thats emitted when an recipient added.
    event RecipientAdded(address recipient, uint256 share);

    /// @notice An event thats emitted when an recipient removed.
    event RecipientRemoved(address recipient);

    /// @notice An event thats emitted when an profit payed to budget.
    event PayToBudget(address recipient, uint256 amount);

    /// @notice An event thats emitted when an profit payed to recipient.
    event PayToRecipient(address recipient, uint256 amount);

    receive() external payable {}

    /**
     * @param _incoming Address of incoming token.
     * @param _uniswapRouter Address of Uniswap router contract.
     */
    constructor(address _incoming, address _uniswapRouter) public {
        incoming = ERC20(_incoming);
        uniswapRouter = IUniswapV2Router02(_uniswapRouter);
    }

    /**
     * @notice Changed uniswap router contract address.
     * @param _uniswapRouter Address new uniswap router contract.
     */
    function changeUniswapRouter(address _uniswapRouter) external onlyOwner {
        uniswapRouter = IUniswapV2Router02(_uniswapRouter);
        emit UniswapRouterChanged(_uniswapRouter);
    }

    /**
     * @notice Changed budget contract address and target balance.
     * @param _budget Address of budget contract.
     * @param _budgetBalance Target budget balance.
     */
    function changeBudget(address payable _budget, uint256 _budgetBalance) external onlyOwner {
        budget = _budget;
        budgetBalance = _budgetBalance;
        emit BudgetChanged(budget, budgetBalance);
    }

    /**
     * @notice Transfer incoming token to recipient.
     * @param _recipient Address of recipient.
     * @param amount Amount of transferred token.
     */
    function transfer(address _recipient, uint256 amount) public onlyOwner {
        require(_recipient != address(0), "ProfitSplitter::transfer: cannot transfer to the zero address");

        incoming.safeTransfer(_recipient, amount);
        emit Transfer(_recipient, amount);
    }

    /**
     * @notice Change incoming token address.
     * @param _incoming New incoming token address.
     * @param _recipient Address of recipient.
     */
    function changeIncoming(address _incoming, address _recipient) external onlyOwner {
        require(address(incoming) != _incoming, "ProfitSplitter::changeIncoming: duplicate incoming token address");

        uint256 balance = incoming.balanceOf(address(this));
        if (balance > 0) {
            transfer(_recipient, balance);
        }
        incoming = ERC20(_incoming);
        emit IncomingChanged(_incoming);
    }

    /**
     * @dev Current share value.
     * @return result Current share value.
     */
    function _currentShare() internal view returns (uint256 result) {
        for (uint256 i = 0; i < recipientsIndex.length(); i++) {
            result = result.add(shares[recipientsIndex.at(i)]);
        }
    }

    /**
     * @notice Add recipient.
     * @param recipient Address of recipient contract.
     * @param share Target share.
     */
    function addRecipient(address recipient, uint256 share) external onlyOwner {
        require(!recipientsIndex.contains(recipient), "ProfitSplitter::addRecipient: recipient already added");
        require(_currentShare().add(share) <= 100, "ProfitSplitter::addRecipient: invalid share");

        recipientsIndex.add(recipient);
        shares[recipient] = share;
        emit RecipientAdded(recipient, share);
    }

    /**
     * @notice Remove recipient.
     * @param recipient Address of recipient contract.
     */
    function removeRecipient(address recipient) external onlyOwner {
        require(recipientsIndex.contains(recipient), "ProfitSplitter::removeRecipient: recipient already removed");

        recipientsIndex.remove(recipient);
        shares[recipient] = 0;
        emit RecipientRemoved(recipient);
    }

    /**
     * @notice Get addresses of recipients.
     * @return Current recipients list.
     */
    function getRecipients() public view returns (address[] memory) {
        address[] memory result = new address[](recipientsIndex.length());

        for (uint256 i = 0; i < recipientsIndex.length(); i++) {
            result[i] = recipientsIndex.at(i);
        }

        return result;
    }

    /**
     * @dev Pay ETH to budget contract.
     */
    function _payToBudget() internal returns (bool) {
        uint256 splitterIncomingBalance = incoming.balanceOf(address(this));
        if (splitterIncomingBalance == 0) return false;

        uint256 currentBudgetBalance = budget.balance;
        if (currentBudgetBalance >= budgetBalance) return false;

        uint256 amount = budgetBalance.sub(currentBudgetBalance);
        uint256 splitterEthBalance = address(this).balance;
        if (splitterEthBalance < amount) {
            uint256 amountOut = amount.sub(splitterEthBalance);

            address[] memory path = new address[](2);
            path[0] = address(incoming);
            path[1] = uniswapRouter.WETH();

            uint256[] memory amountsIn = uniswapRouter.getAmountsIn(amountOut, path);
            require(amountsIn.length == 2, "ProfitSplitter::_payToBudget: invalid amounts in length");
            require(amountsIn[0] > 0, "ProfitSplitter::_payToBudget: liquidity pool is empty");
            if (amountsIn[0] <= splitterIncomingBalance) {
                incoming.safeApprove(address(uniswapRouter), amountsIn[0]);
                uniswapRouter.swapTokensForExactETH(amountOut, amountsIn[0], path, address(this), block.timestamp);
            } else {
                uint256[] memory amountsOut = uniswapRouter.getAmountsOut(splitterIncomingBalance, path);
                require(amountsOut.length == 2, "ProfitSplitter::_payToBudget: invalid amounts out length");
                require(amountsOut[1] > 0, "ProfitSplitter::_payToBudget: amounts out liquidity pool is empty");

                amount = amountsOut[1];

                incoming.safeApprove(address(uniswapRouter), splitterIncomingBalance);
                uniswapRouter.swapExactTokensForETH(splitterIncomingBalance, amountsOut[1], path, address(this), block.timestamp);
            }
        }

        budget.transfer(amount);
        emit PayToBudget(budget, amount);

        return true;
    }

    /**
     * @dev Pay incoming token to all recipients.
     */
    //  SWC-107-Reentrancy: L228
    function _payToRecipients() internal returns (bool) {
        uint256 splitterIncomingBalance = incoming.balanceOf(address(this));
        if (splitterIncomingBalance == 0) return false;

        for (uint256 i = 0; i < recipientsIndex.length(); i++) {
            address recipient = recipientsIndex.at(i);
            uint256 share = shares[recipient];

            uint256 amount = splitterIncomingBalance.mul(10**SHARE_ACCURACY).mul(share).div(10**SHARE_ACCURACY.add(SHARE_DIGITS));
            incoming.safeTransfer(recipient, amount);

            emit PayToRecipient(recipient, amount);
        }

        return true;
    }

    /**
     * @notice Split all incoming token balance to recipients and budget contract.
     * @param amount Approved amount incoming token.
     */
    function split(uint256 amount) external whenNotPaused {
        if (amount > 0) {
            incoming.safeTransferFrom(_msgSender(), address(this), amount);
        }

        _payToBudget();
        _payToRecipients();
    }
}
