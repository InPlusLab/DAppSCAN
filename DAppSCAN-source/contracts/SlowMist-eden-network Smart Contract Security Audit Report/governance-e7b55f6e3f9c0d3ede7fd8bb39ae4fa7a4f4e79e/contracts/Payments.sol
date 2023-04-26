// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./interfaces/IERC20Permit.sol";
import "./lib/SafeERC20.sol";
import "./lib/ReentrancyGuard.sol";

/**
 * @title Payments
 * @dev Contract for streaming token payments for set periods of time 
 */
contract Payments is ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Payment definition
    struct Payment {
        address token;
        address receiver;
        address payer;
        uint48 startTime;
        uint48 stopTime;
        uint16 cliffDurationInDays;
        uint256 paymentDurationInSecs;
        uint256 amount;
        uint256 amountClaimed;
    }

    /// @notice Payment balance definition
    struct PaymentBalance {
        uint256 id;
        uint256 claimableAmount;
        Payment payment;
    }

    /// @notice Token balance definition
    struct TokenBalance {
        uint256 totalAmount;
        uint256 claimableAmount;
        uint256 claimedAmount;
    }

    /// @dev Used to translate payment periods specified in days to seconds
    uint256 constant internal SECONDS_PER_DAY = 86400;
    
    /// @notice Mapping of payment id > token payments
    mapping (uint256 => Payment) public tokenPayments;

    /// @notice Mapping of address to payment id
    mapping (address => uint256[]) public paymentIds;

    /// @notice Number of payments
    uint256 public numPayments;

    /// @notice Event emitted when a new payment is created
    event PaymentCreated(address indexed token, address indexed payer, address indexed receiver, uint256 paymentId, uint256 amount, uint48 startTime, uint256 durationInSecs, uint16 cliffInDays);
    
    /// @notice Event emitted when tokens are claimed by a receiver from an available balance
    event TokensClaimed(address indexed receiver, address indexed token, uint256 indexed paymentId, uint256 amountClaimed);

    /// @notice Event emitted when payment stopped
    event PaymentStopped(uint256 indexed paymentId, uint256 indexed originalDuration, uint48 stopTime, uint48 startTime);

    /**
     * @notice Create payment, optionally providing voting power
     * @param payer The account that is paymenting tokens
     * @param receiver The account that will be able to retrieve available tokens
     * @param startTime The unix timestamp when the payment period will start
     * @param amount The amount of tokens being paid
     * @param paymentDurationInSecs The payment period in seconds
     * @param cliffDurationInDays The cliff duration in days
     */
    function createPayment(
        address token,
        address payer,
        address receiver,
        uint48 startTime,
        uint256 amount,
        uint256 paymentDurationInSecs,
        uint16 cliffDurationInDays
    )
        external
    {
        require(paymentDurationInSecs > 0, "Payments::createPayment: payment duration must be > 0");
        require(paymentDurationInSecs <= 25*365*SECONDS_PER_DAY, "Payments::createPayment: payment duration more than 25 years");
        require(paymentDurationInSecs >= SECONDS_PER_DAY*cliffDurationInDays, "Payments::createPayment: payment duration < cliff");
        require(amount > 0, "Payments::createPayment: amount not > 0");
        _createPayment(token, payer, receiver, startTime, amount, paymentDurationInSecs, cliffDurationInDays);
    }

    /**
     * @notice Create payment, using permit for approval
     * @dev It is up to the frontend developer to ensure the token implements permit - otherwise this will fail
     * @param token Address of token to payment
     * @param payer The account that is paymenting tokens
     * @param receiver The account that will be able to retrieve available tokens
     * @param startTime The unix timestamp when the payment period will start
     * @param amount The amount of tokens being paid
     * @param paymentDurationInSecs The payment period in seconds
     * @param cliffDurationInDays The payment cliff duration in days
     * @param deadline The time at which to expire the signature
     * @param v The recovery byte of the signature
     * @param r Half of the ECDSA signature pair
     * @param s Half of the ECDSA signature pair
     */
    function createPaymentWithPermit(
        address token,
        address payer,
        address receiver,
        uint48 startTime,
        uint256 amount,
        uint256 paymentDurationInSecs,
        uint16 cliffDurationInDays,
        uint256 deadline,
        uint8 v, 
        bytes32 r, 
        bytes32 s
    ) 
        external
    {
        require(paymentDurationInSecs > 0, "Payments::createPaymentWithPermit: payment duration must be > 0");
        require(paymentDurationInSecs <= 25*365*SECONDS_PER_DAY, "Payments::createPaymentWithPermit: payment duration more than 25 years");
        require(paymentDurationInSecs >= SECONDS_PER_DAY*cliffDurationInDays, "Payments::createPaymentWithPermit: duration < cliff");
        require(amount > 0, "Payments::createPaymentWithPermit: amount not > 0");

        // Set approval using permit signature
        IERC20Permit(token).permit(payer, address(this), amount, deadline, v, r, s);
        _createPayment(token, payer, receiver, startTime, amount, paymentDurationInSecs, cliffDurationInDays);
    }

    /**
     * @notice Get all active token payment ids
     * @return the payment ids
     */
    function allActivePaymentIds() external view returns(uint256[] memory){
        uint256 activeCount;

        // Get number of active payments
        for (uint256 i; i < numPayments; i++) {
            if(claimableBalance(i) > 0) {
                activeCount++;
            }
        }

        // Create result array of length `activeCount`
        uint256[] memory result = new uint256[](activeCount);
        uint256 j;

        // Populate result array
        for (uint256 i; i < numPayments; i++) {
            if(claimableBalance(i) > 0) {
                result[j] = i;
                j++;
            }
        }
        return result;
    }

    /**
     * @notice Get all active token payments
     * @return the payments
     */
    function allActivePayments() external view returns(Payment[] memory){
        uint256 activeCount;

        // Get number of active payments
        for (uint256 i; i < numPayments; i++) {
            if(claimableBalance(i) > 0) {
                activeCount++;
            }
        }

        // Create result array of length `activeCount`
        Payment[] memory result = new Payment[](activeCount);
        uint256 j;

        // Populate result array
        for (uint256 i; i < numPayments; i++) {
            if(claimableBalance(i) > 0) {
                result[j] = tokenPayments[i];
                j++;
            }
        }
        return result;
    }

    /**
     * @notice Get all active token payment balances
     * @return the active payment balances
     */
    function allActivePaymentBalances() external view returns(PaymentBalance[] memory){
        uint256 activeCount;

        // Get number of active payments
        for (uint256 i; i < numPayments; i++) {
            if(claimableBalance(i) > 0) {
                activeCount++;
            }
        }

        // Create result array of length `activeCount`
        PaymentBalance[] memory result = new PaymentBalance[](activeCount);
        uint256 j;

        // Populate result array
        for (uint256 i; i < numPayments; i++) {
            if(claimableBalance(i) > 0) {
                result[j] = paymentBalance(i);
                j++;
            }
        }
        return result;
    }

    /**
     * @notice Get all active token payment ids for receiver
     * @param receiver The address that has paid balances
     * @return the active payment ids
     */
    function activePaymentIds(address receiver) external view returns(uint256[] memory){
        uint256 activeCount;
        uint256[] memory receiverPaymentIds = paymentIds[receiver];

        // Get number of active payments
        for (uint256 i; i < receiverPaymentIds.length; i++) {
            if(claimableBalance(receiverPaymentIds[i]) > 0) {
                activeCount++;
            }
        }

        // Create result array of length `activeCount`
        uint256[] memory result = new uint256[](activeCount);
        uint256 j;

        // Populate result array
        for (uint256 i; i < receiverPaymentIds.length; i++) {
            if(claimableBalance(receiverPaymentIds[i]) > 0) {
                result[j] = receiverPaymentIds[i];
                j++;
            }
        }
        return result;
    }

    /**
     * @notice Get all token payments for receiver
     * @param receiver The address that has paid balances
     * @return the payments
     */
    function allPayments(address receiver) external view returns(Payment[] memory){
        uint256[] memory allPaymentIds = paymentIds[receiver];
        Payment[] memory result = new Payment[](allPaymentIds.length);
        for (uint256 i; i < allPaymentIds.length; i++) {
            result[i] = tokenPayments[allPaymentIds[i]];
        }
        return result;
    }

    /**
     * @notice Get all active token payments for receiver
     * @param receiver The address that has paid balances
     * @return the payments
     */
    function activePayments(address receiver) external view returns(Payment[] memory){
        uint256 activeCount;
        uint256[] memory receiverPaymentIds = paymentIds[receiver];

        // Get number of active payments
        for (uint256 i; i < receiverPaymentIds.length; i++) {
            if(claimableBalance(receiverPaymentIds[i]) > 0) {
                activeCount++;
            }
        }

        // Create result array of length `activeCount`
        Payment[] memory result = new Payment[](activeCount);
        uint256 j;

        // Populate result array
        for (uint256 i; i < receiverPaymentIds.length; i++) {
            if(claimableBalance(receiverPaymentIds[i]) > 0) {
                result[j] = tokenPayments[receiverPaymentIds[i]];
                j++;
            }
        }
        return result;
    }

    /**
     * @notice Get all active token payment balances for receiver
     * @param receiver The address that has paid balances
     * @return the active payment balances
     */
    function activePaymentBalances(address receiver) external view returns(PaymentBalance[] memory){
        uint256 activeCount;
        uint256[] memory receiverPaymentIds = paymentIds[receiver];

        // Get number of active payments
        for (uint256 i; i < receiverPaymentIds.length; i++) {
            if(claimableBalance(receiverPaymentIds[i]) > 0) {
                activeCount++;
            }
        }

        // Create result array of length `activeCount`
        PaymentBalance[] memory result = new PaymentBalance[](activeCount);
        uint256 j;

        // Populate result array
        for (uint256 i; i < receiverPaymentIds.length; i++) {
            if(claimableBalance(receiverPaymentIds[i]) > 0) {
                result[j] = paymentBalance(receiverPaymentIds[i]);
                j++;
            }
        }
        return result;
    }

    /**
     * @notice Get total token balance
     * @param token The token to check
     * @return balance the total active balance of `token`
     */
    function totalTokenBalance(address token) external view returns(TokenBalance memory balance){
        for (uint256 i; i < numPayments; i++) {
            Payment memory tokenPayment = tokenPayments[i];
            if(tokenPayment.token == token && tokenPayment.startTime != tokenPayment.stopTime){
                balance.totalAmount = balance.totalAmount + tokenPayment.amount;
                if(block.timestamp > tokenPayment.startTime) {
                    balance.claimedAmount = balance.claimedAmount + tokenPayment.amountClaimed;

                    uint256 elapsedTime = tokenPayment.stopTime > 0 && tokenPayment.stopTime < block.timestamp ? tokenPayment.stopTime - tokenPayment.startTime : block.timestamp - tokenPayment.startTime;
                    uint256 elapsedDays = elapsedTime / SECONDS_PER_DAY;

                    if (
                        elapsedDays >= tokenPayment.cliffDurationInDays
                    ) {
                        if (tokenPayment.stopTime == 0 && elapsedTime >= tokenPayment.paymentDurationInSecs) {
                            balance.claimableAmount = balance.claimableAmount + tokenPayment.amount - tokenPayment.amountClaimed;
                        } else {
                            uint256 paymentAmountPerSec = tokenPayment.amount / tokenPayment.paymentDurationInSecs;
                            uint256 amountAvailable = paymentAmountPerSec * elapsedTime;
                            balance.claimableAmount = balance.claimableAmount + amountAvailable - tokenPayment.amountClaimed;
                        }
                    }
                }
            }
        }
    }

    /**
     * @notice Get token balance of receiver
     * @param token The token to check
     * @param receiver The address that has available balances
     * @return balance the total active balance of `token` for `receiver`
     */
    function tokenBalance(address token, address receiver) external view returns(TokenBalance memory balance){
        uint256[] memory receiverPaymentIds = paymentIds[receiver];
        for (uint256 i; i < receiverPaymentIds.length; i++) {
            Payment memory receiverPayment = tokenPayments[receiverPaymentIds[i]];
            if(receiverPayment.token == token && receiverPayment.startTime != receiverPayment.stopTime){
                balance.totalAmount = balance.totalAmount + receiverPayment.amount;
                if(block.timestamp > receiverPayment.startTime) {
                    balance.claimedAmount = balance.claimedAmount + receiverPayment.amountClaimed;

                    uint256 elapsedTime = receiverPayment.stopTime > 0 && receiverPayment.stopTime < block.timestamp ? receiverPayment.stopTime - receiverPayment.startTime : block.timestamp - receiverPayment.startTime;
                    uint256 elapsedDays = elapsedTime / SECONDS_PER_DAY;

                    if (
                        elapsedDays >= receiverPayment.cliffDurationInDays
                    ) {
                        if (receiverPayment.stopTime == 0 && elapsedTime >= receiverPayment.paymentDurationInSecs) {
                            balance.claimableAmount = balance.claimableAmount + receiverPayment.amount - receiverPayment.amountClaimed;
                        } else {
                            uint256 paymentAmountPerSec = receiverPayment.amount / receiverPayment.paymentDurationInSecs;
                            uint256 amountAvailable = paymentAmountPerSec * elapsedTime;
                            balance.claimableAmount = balance.claimableAmount + amountAvailable - receiverPayment.amountClaimed;
                        }
                    }
                }
            }
        }
    }

    /**
     * @notice Get payment balance for a given payment id
     * @param paymentId The payment ID
     * @return balance the payment balance
     */
    function paymentBalance(uint256 paymentId) public view returns (PaymentBalance memory balance) {
        balance.id = paymentId;
        balance.claimableAmount = claimableBalance(paymentId);
        balance.payment = tokenPayments[paymentId];
    }

    /**
     * @notice Get claimable balance for a given payment id
     * @dev Returns 0 if cliff duration has not ended
     * @param paymentId The payment ID
     * @return The amount that can be claimed
     */
    function claimableBalance(uint256 paymentId) public view returns (uint256) {
        Payment storage payment = tokenPayments[paymentId];

        // For payments created with a future start date or payments stopped before starting, that hasn't been reached, return 0
        if (block.timestamp < payment.startTime || payment.startTime == payment.stopTime) {
            return 0;
        }

        
        uint256 elapsedTime = payment.stopTime > 0 && payment.stopTime < block.timestamp ? payment.stopTime - payment.startTime : block.timestamp - payment.startTime;
        uint256 elapsedDays = elapsedTime / SECONDS_PER_DAY;
        
        if (elapsedDays < payment.cliffDurationInDays) {
            return 0;
        }

        if (payment.stopTime == 0 && elapsedTime >= payment.paymentDurationInSecs) {
            return payment.amount - payment.amountClaimed;
        }
        
        uint256 paymentAmountPerSec = payment.amount / payment.paymentDurationInSecs;
        uint256 amountAvailable = paymentAmountPerSec * elapsedTime;
        return amountAvailable - payment.amountClaimed;
    }

    /**
     * @notice Allows receiver to claim all of their available tokens for a set of payments
     * @dev Errors if no tokens are claimable
     * @dev It is advised receivers check they are entitled to claim via `claimableBalance` before calling this
     * @param payments The payment ids for available token balances
     */
    function claimAllAvailableTokens(uint256[] memory payments) external nonReentrant {
        for (uint i = 0; i < payments.length; i++) {
            uint256 claimableAmount = claimableBalance(payments[i]);
            require(claimableAmount > 0, "Payments::claimAllAvailableTokens: claimableAmount is 0");
            _claimTokens(payments[i], claimableAmount);
        }
    }

    /**
     * @notice Allows receiver to claim a portion of their available tokens for a given payment
     * @dev Errors if token amounts provided are > claimable amounts
     * @dev It is advised receivers check they are entitled to claim via `claimableBalance` before calling this
     * @param payments The payment ids for available token balances
     * @param amounts The amount of each available token to claim
     */
    function claimAvailableTokenAmounts(uint256[] memory payments, uint256[] memory amounts) external nonReentrant {
        require(payments.length == amounts.length, "Payments::claimAvailableTokenAmounts: arrays must be same length");
        for (uint i = 0; i < payments.length; i++) {
            uint256 claimableAmount = claimableBalance(payments[i]);
            require(claimableAmount >= amounts[i], "Payments::claimAvailableTokenAmounts: claimableAmount < amount");
            _claimTokens(payments[i], amounts[i]);
        }
    }

    /**
     * @notice Allows payer or receiver to stop existing payments for a given paymentId
     * @param paymentId The payment id for a payment
     * @param stopTime Timestamp to stop payment, if 0 use current block.timestamp
     */
    function stopPayment(uint256 paymentId, uint48 stopTime) external nonReentrant {
        Payment storage payment = tokenPayments[paymentId];
        require(msg.sender == payment.payer || msg.sender == payment.receiver, "Payments::stopPayment: msg.sender must be payer or receiver");
        require(payment.stopTime == 0, "Payments::stopPayment: payment already stopped");
        stopTime = stopTime == 0 ? uint48(block.timestamp) : stopTime;
        require(stopTime < payment.startTime + payment.paymentDurationInSecs, "Payments::stopPayment: stop time > payment duration");
        if(stopTime > payment.startTime) {
            payment.stopTime = stopTime;
            uint256 newPaymentDuration = stopTime - payment.startTime;
            uint256 paymentAmountPerSec = payment.amount / payment.paymentDurationInSecs;
            uint256 newPaymentAmount = paymentAmountPerSec * newPaymentDuration;
            IERC20(payment.token).safeTransfer(payment.payer, payment.amount - newPaymentAmount);
            emit PaymentStopped(paymentId, payment.paymentDurationInSecs, stopTime, payment.startTime);
        } else {
            payment.stopTime = payment.startTime;
            IERC20(payment.token).safeTransfer(payment.payer, payment.amount);
            emit PaymentStopped(paymentId, payment.paymentDurationInSecs, payment.startTime, payment.startTime);
        }
    }

    /**
     * @notice Internal implementation of createPayment
     * @param payer The account that is paymenting tokens
     * @param receiver The account that will be able to retrieve available tokens
     * @param startTime The unix timestamp when the payment period will start
     * @param amount The amount of tokens being paid
     * @param paymentDurationInSecs The payment period in seconds
     * @param cliffDurationInDays The cliff duration in days
     */
    function _createPayment(
        address token,
        address payer,
        address receiver,
        uint48 startTime,
        uint256 amount,
        uint256 paymentDurationInSecs,
        uint16 cliffDurationInDays
    ) internal {

        // Transfer the tokens under the control of the payment contract
        IERC20(token).safeTransferFrom(payer, address(this), amount);

        uint48 paymentStartTime = startTime == 0 ? uint48(block.timestamp) : startTime;

        // Create payment
        Payment memory payment = Payment({
            token: token,
            receiver: receiver,
            payer: payer,
            startTime: paymentStartTime,
            stopTime: 0,
            paymentDurationInSecs: paymentDurationInSecs,
            cliffDurationInDays: cliffDurationInDays,
            amount: amount,
            amountClaimed: 0
        });

        tokenPayments[numPayments] = payment;
        paymentIds[receiver].push(numPayments);
        emit PaymentCreated(token, payer, receiver, numPayments, amount, paymentStartTime, paymentDurationInSecs, cliffDurationInDays);
        
        // Increment payment id
        numPayments++;
    }

    /**
     * @notice Internal implementation of token claims
     * @param paymentId The payment id for claim
     * @param claimAmount The amount to claim
     */
    function _claimTokens(uint256 paymentId, uint256 claimAmount) internal {
        Payment storage payment = tokenPayments[paymentId];

        // Update claimed amount
        payment.amountClaimed = payment.amountClaimed + claimAmount;

        // Release tokens
        IERC20(payment.token).safeTransfer(payment.receiver, claimAmount);
        emit TokensClaimed(payment.receiver, payment.token, paymentId, claimAmount);
    }
}