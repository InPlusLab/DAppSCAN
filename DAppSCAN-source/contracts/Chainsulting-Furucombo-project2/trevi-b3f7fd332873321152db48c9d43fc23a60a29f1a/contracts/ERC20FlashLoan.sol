// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./libraries/SafeERC20.sol";
import "./libraries/SafeMath.sol";
import "./interfaces/IFlashLender.sol";

contract ERC20FlashLoan is IFlashLender {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    IERC20 public immutable lendingToken;
    uint256 public flashLoanFee;
    uint256 public constant FEE_BASE = 1e4;
    bytes32 private constant _RETURN_VALUE =
        keccak256("ERC3156FlashBorrower.onFlashLoan");

    constructor(IERC20 token, uint256 fee) public {
        require(fee <= FEE_BASE, "ERC20FlashLoan: fee rate exceeded");
        lendingToken = token;
        flashLoanFee = fee;
    }

    /**
     * @dev The amount of currency available to be lended.
     * @param token The loan currency.
     * @return The amount of `token` that can be borrowed.
     */
    function maxFlashLoan(address token)
        external
        view
        override
        returns (uint256)
    {
        return
            token == address(lendingToken)
                ? lendingToken.balanceOf(address(this))
                : 0;
    }

    /**
     * @dev The fee to be charged for a given loan.
     * @param token The loan currency.
     * @param amount The amount of tokens lent.
     * @return The amount of `token` to be charged for the loan, on top of the returned principal.
     */
    function flashFee(address token, uint256 amount)
        public
        view
        override
        returns (uint256)
    {
        require(token == address(lendingToken), "ERC20FlashLoan: wrong token");
        return amount.mul(flashLoanFee).div(FEE_BASE);
    }

    /**
     * @dev Initiate a flash loan.
     * @param receiver The receiver of the tokens in the loan, and the receiver of the callback.
     * @param token The loan currency.
     * @param amount The amount of tokens lent.
     * @param data Arbitrary data structure, intended to contain user-defined parameters.
     */
    function flashLoan(
        IERC3156FlashBorrower receiver,
        address token,
        uint256 amount,
        bytes calldata data
    ) public override returns (bool) {
        uint256 fee = flashFee(token, amount);
        // send token to receiver
        lendingToken.safeTransfer(address(receiver), amount);
        require(
            receiver.onFlashLoan(msg.sender, token, amount, fee, data) ==
                _RETURN_VALUE,
            "ERC20FlashLoan: invalid return value"
        );
        uint256 currentAllowance =
            lendingToken.allowance(address(receiver), address(this));
        uint256 totalDebt = amount.add(fee);
        require(
            currentAllowance >= totalDebt,
            "ERC20FlashLoan: allowance does not allow refund"
        );
        // get token from receiver
        lendingToken.safeTransferFrom(
            address(receiver),
            address(this),
            totalDebt
        );
        address collector = flashLoanFeeCollector();
        if (collector != address(0)) lendingToken.safeTransfer(collector, fee);

        return true;
    }

    function flashLoanFeeCollector()
        public
        view
        virtual
        override
        returns (address)
    {
        this;
        return address(0);
    }

    function setFlashLoanFee(uint256 fee) public virtual override {
        require(fee <= FEE_BASE, "ERC20FlashLoan: fee rate exceeded");
        flashLoanFee = fee;
    }
}
