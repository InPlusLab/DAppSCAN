// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "../utils/OwnablePausable.sol";
import "../uniswap/IUniswapV2Router02.sol";

contract Buyback is OwnablePausable {
    using SafeMath for uint256;
    using SafeERC20 for ERC20;

    /// @notice Incoming token.
    ERC20 public incoming;

    /// @notice Outcoming token.
    ERC20 public outcoming;

    /// @notice Recipient address.
    address public recipient;

    /// @notice Uniswap router contract address.
    IUniswapV2Router02 public uniswapRouter;

    /// @notice An event thats emitted when an incoming token transferred to recipient.
    event Transfer(address recipient, uint256 amount);

    /// @notice An event thats emitted when an recipient address changed.
    event RecipientChanged(address newRecipient);

    /// @notice An event thats emitted when an incoming token changed.
    event IncomingChanged(address newIncoming);

    /// @notice An event thats emitted when an uniswap router contract address changed.
    event UniswapRouterChanged(address newUniswapRouter);

    /// @notice An event thats emitted when an buyback successed.
    event BuybackSuccessed(uint256 incoming, uint256 outcoming);

    /**
     * @param _incoming Address of incoming token.
     * @param _outcoming Address of outcoming token.
     * @param _recipient Address of recipient outcoming token.
     * @param _uniswapRouter Address of Uniswap router contract.
     */
    constructor(
        address _incoming,
        address _outcoming,
        address _recipient,
        address _uniswapRouter
    ) public {
        incoming = ERC20(_incoming);
        outcoming = ERC20(_outcoming);
        recipient = _recipient;
        uniswapRouter = IUniswapV2Router02(_uniswapRouter);
    }

    /**
     * @notice Change recipient address.
     * @param _recipient New recipient address.
     */
    function changeRecipient(address _recipient) external onlyOwner {
        recipient = _recipient;
        emit RecipientChanged(recipient);
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
     * @notice Transfer incoming token to recipient.
     * @param _recipient Address of recipient.
     * @param amount Amount of transferred token.
     */
    function transfer(address _recipient, uint256 amount) public onlyOwner {
        require(_recipient != address(0), "Buyback::transfer: cannot transfer to the zero address");

        incoming.safeTransfer(_recipient, amount);
        emit Transfer(_recipient, amount);
    }

    /**
     * @notice Change incoming token address.
     * @param _incoming New incoming token address.
     * @param _recipient Address of recipient.
     */
    function changeIncoming(address _incoming, address _recipient) external onlyOwner {
        require(address(incoming) != _incoming, "Buyback::changeIncoming: duplicate incoming token address");

        uint256 balance = incoming.balanceOf(address(this));
        if (balance > 0) {
            transfer(_recipient, balance);
        }
        incoming = ERC20(_incoming);
        emit IncomingChanged(_incoming);
    }

    /**
     * @notice Make buyback attempt.
     * @param amount Amount of tokens to buyback.
     */
    function buy(uint256 amount) external whenNotPaused {
        if (amount > 0) {
            incoming.safeTransferFrom(_msgSender(), address(this), amount);
        }

        address[] memory path = new address[](2);
        path[0] = address(incoming);
        path[1] = address(outcoming);

        uint256 amountIn = incoming.balanceOf(address(this));
        require(amountIn > 0, "Buyback::buy: incoming token balance is empty");
        uint256[] memory amountsOut = uniswapRouter.getAmountsOut(amountIn, path);
        require(amountsOut.length != 0, "Buyback::buy: invalid amounts out length");
        uint256 amountOut = amountsOut[amountsOut.length - 1];
        require(amountOut > 0, "Buyback::buy: liquidity pool is empty");

        incoming.safeApprove(address(uniswapRouter), amountIn);
        uniswapRouter.swapExactTokensForTokens(amountIn, amountOut, path, recipient, block.timestamp);
        emit BuybackSuccessed(amountIn, amountOut);
    }
}
