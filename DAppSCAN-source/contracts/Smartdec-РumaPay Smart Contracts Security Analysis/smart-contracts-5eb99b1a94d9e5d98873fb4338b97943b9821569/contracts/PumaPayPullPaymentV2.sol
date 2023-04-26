pragma solidity 0.5.8;

import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-solidity/contracts/token/ERC20/ERC20Mintable.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "./ownership/PayableOwnable.sol";

/// @title PumaPay Pull Payment V2.0 - Contract that facilitates our pull payment protocol
/// V2.0 of the protocol removes the rates being set globally on the smart contract and it allows to pass the rate on
/// pull payment registration and pull payment execution. In addition, when a registration of a pull payment takes place
/// the first execution of the pull payment happens as well.
/// @author PumaPay Dev Team - <developers@pumapay.io>
contract PumaPayPullPaymentV2 is PayableOwnable {

    using SafeMath for uint256;

    /// ===============================================================================================================
    ///                                      Events
    /// ===============================================================================================================

    event LogExecutorAdded(address executor);
    event LogExecutorRemoved(address executor);

    event LogPaymentRegistered(
        address customerAddress,
        bytes32 paymentID,
        bytes32 businessID,
        bytes32 uniqueReferenceID
    );

    event LogPaymentCancelled(
        address customerAddress,
        bytes32 paymentID,
        bytes32 businessID,
        bytes32 uniqueReferenceID
    );

    event LogPullPaymentExecuted(
        address customerAddress,
        bytes32 paymentID,
        bytes32 businessID,
        bytes32 uniqueReferenceID,
        uint256 amountInPMA,
        uint256 conversionRate
    );

    /// ===============================================================================================================
    ///                                      Constants
    /// ===============================================================================================================
    uint256 constant private DECIMAL_FIXER = 10 ** 10; /// 1e^10 - This transforms the Rate from decimals to uint256
    uint256 constant private FIAT_TO_CENT_FIXER = 100;    /// Fiat currencies have 100 cents in 1 basic monetary unit.
    uint256 constant private OVERFLOW_LIMITER_NUMBER = 10 ** 20; /// 1e^20 - Prevent numeric overflows

    uint256 constant private ONE_ETHER = 1 ether;         /// PumaPay token has 18 decimals - same as one ETHER
    uint256 constant private FUNDING_AMOUNT = 1 ether;  /// Amount to transfer to owner/executor
    uint256 constant private MINIMUM_AMOUNT_OF_ETH_FOR_OPERATORS = 0.15 ether; /// min amount of ETH for owner/executor

    bytes32 constant private TYPE_SINGLE_PULL_PAYMENT = "2";
    bytes32 constant private TYPE_RECURRING_PULL_PAYMENT = "3";
    bytes32 constant private TYPE_RECURRING_PULL_PAYMENT_WITH_INITIAL = "4";
    bytes32 constant private TYPE_PULL_PAYMENT_WITH_FREE_TRIAL = "5";
    bytes32 constant private TYPE_PULL_PAYMENT_WITH_PAID_TRIAL = "6";
    bytes32 constant private TYPE_SINGLE_DYNAMIC_PULL_PAYMENT = "7";

    /// ===============================================================================================================
    ///                                      Members
    /// ===============================================================================================================

    IERC20 public token;

    mapping(address => bool) public executors;
    mapping(address => mapping(address => PullPayment)) public pullPayments;

    struct PullPayment {
        bytes32[3] paymentIds;                  /// [0] paymentID / [1] businessID / [2] uniqueReferenceID
        bytes32 paymentType;                    /// Type of Pull Payment - must be one of the defined pull payment types
        string currency;                        /// 3-letter abbr i.e. 'EUR' / 'USD' etc.
        uint256 initialConversionRate;          /// conversion rate for first payment execution
        uint256 initialPaymentAmountInCents;    /// initial payment amount in fiat in cents
        uint256 fiatAmountInCents;              /// payment amount in fiat in cents
        uint256 frequency;                      /// how often merchant can pull - in seconds
        uint256 numberOfPayments;               /// amount of pull payments merchant can make
        uint256 startTimestamp;                 /// when subscription starts - in seconds
        uint256 trialPeriod;                    /// trial period of the pull payment - in seconds
        uint256 nextPaymentTimestamp;           /// timestamp of next payment
        uint256 lastPaymentTimestamp;           /// timestamp of last payment
        uint256 cancelTimestamp;                /// timestamp the payment was cancelled
        address treasuryAddress;                /// address which pma tokens will be transfer to on execution
    }

    /// ===============================================================================================================
    ///                                      Modifiers
    /// ===============================================================================================================
    modifier isExecutor() {
        require(executors[msg.sender], "msg.sender not an executor");
        _;
    }

    modifier executorExists(address _executor) {
        require(executors[_executor], "Executor does not exists.");
        _;
    }

    modifier executorDoesNotExists(address _executor) {
        require(!executors[_executor], "Executor already exists.");
        _;
    }

    modifier paymentExists(address _customerAddress, address _pullPaymentExecutor) {
        require(doesPaymentExist(_customerAddress, _pullPaymentExecutor), "Pull Payment does not exists");
        _;
    }

    modifier paymentNotCancelled(address _customerAddress, address _pullPaymentExecutor) {
        require(pullPayments[_customerAddress][_pullPaymentExecutor].cancelTimestamp == 0, "Pull Payment is cancelled");
        _;
    }

    modifier isValidPullPaymentExecutionRequest(
        address _customerAddress,
        address _pullPaymentExecutor,
        bytes32 _paymentID) {

        require((pullPayments[_customerAddress][_pullPaymentExecutor].initialPaymentAmountInCents > 0 ||
        (now >= pullPayments[_customerAddress][_pullPaymentExecutor].startTimestamp &&
        now >= pullPayments[_customerAddress][_pullPaymentExecutor].nextPaymentTimestamp)
            ), "Invalid pull payment execution request - Time of execution is invalid."
        );
        require(pullPayments[_customerAddress][_pullPaymentExecutor].numberOfPayments > 0,
            "Invalid pull payment execution request - Number of payments is zero.");

        require(
            (pullPayments[_customerAddress][_pullPaymentExecutor].cancelTimestamp == 0 ||
        pullPayments[_customerAddress][_pullPaymentExecutor].cancelTimestamp >
        pullPayments[_customerAddress][_pullPaymentExecutor].nextPaymentTimestamp),
            "Invalid pull payment execution request - Pull payment is cancelled");
        require(keccak256(
            abi.encodePacked(pullPayments[_customerAddress][_pullPaymentExecutor].paymentIds[0])
        ) == keccak256(abi.encodePacked(_paymentID)),
            "Invalid pull payment execution request - Payment ID not matching.");
        _;
    }

    modifier isValidDeletionRequest(bytes32 _paymentID, address _customerAddress, address _pullPaymentExecutor) {
        require(_customerAddress != address(0), "Invalid deletion request - Client address is ZERO_ADDRESS.");
        require(_pullPaymentExecutor != address(0), "Invalid deletion request - Beneficiary address is ZERO_ADDRESS.");
        require(_paymentID.length != 0, "Invalid deletion request - Payment ID is empty.");
        _;
    }

    modifier isValidAddress(address _address) {
        require(_address != address(0), "Invalid address - ZERO_ADDRESS provided");
        _;
    }

    modifier validAmount(uint256 _amount) {
        require(_amount > 0, "Invalid amount - Must be higher than zero");
        require(_amount < OVERFLOW_LIMITER_NUMBER, "Invalid amount - Must be lower than the overflow limit.");
        _;
    }

    modifier isValidPaymentType(bytes32 _paymentType) {
        require(_paymentType.length > 0, "Payment Type is empty.");
        require(
            (
            _paymentType == TYPE_SINGLE_PULL_PAYMENT ||
            _paymentType == TYPE_RECURRING_PULL_PAYMENT ||
            _paymentType == TYPE_RECURRING_PULL_PAYMENT_WITH_INITIAL ||
            _paymentType == TYPE_PULL_PAYMENT_WITH_FREE_TRIAL ||
            _paymentType == TYPE_PULL_PAYMENT_WITH_PAID_TRIAL
            ), "Payment Type provided not supported");
        _;
    }

    /// ===============================================================================================================
    ///                                      Constructor
    /// ===============================================================================================================

    /// @dev Contract constructor - sets the token address that the contract facilitates.
    /// @param _token Token Address.
    constructor(address _token)
    public {
        require(_token != address(0), "Invalid address for token - ZERO_ADDRESS provided");

        token = IERC20(_token);
    }

    // @notice Will receive any eth sent to the contract
    function() external payable {
    }

    /// ===============================================================================================================
    ///                                      Public Functions - Owner Only
    /// ===============================================================================================================

    /// @dev Adds a new executor. - can be executed only by the onwer.
    /// When adding a new executor 1 ETH is tranferred to allow the executor to pay for gas.
    /// The balance of the owner is also checked and if funding is needed 1 ETH is transferred.
    /// @param _executor - address of the executor which cannot be zero address.
    function addExecutor(address payable _executor)
    public
    onlyOwner
    isValidAddress(_executor)
    executorDoesNotExists(_executor)
    {
        _executor.transfer(FUNDING_AMOUNT);
        executors[_executor] = true;

        if (isFundingNeeded(owner())) {
            owner().transfer(FUNDING_AMOUNT);
        }

        emit LogExecutorAdded(_executor);
    }

    /// @dev Removes a new executor. - can be executed only by the onwer.
    /// The balance of the owner is checked and if funding is needed 1 ETH is transferred.
    /// @param _executor - address of the executor which cannot be zero address.
    function removeExecutor(address payable _executor)
    public
    onlyOwner
    isValidAddress(_executor)
    executorExists(_executor)
    {
        executors[_executor] = false;
        if (isFundingNeeded(owner())) {
            owner().transfer(FUNDING_AMOUNT);
        }
        emit LogExecutorRemoved(_executor);
    }

    /// ===============================================================================================================
    ///                                      Public Functions - Executors Only
    /// ===============================================================================================================

    /// @dev Registers a new pull payment to the PumaPay Pull Payment Contract - The registration can be executed only
    /// by one of the executors of the PumaPay Pull Payment Contract
    /// and the PumaPay Pull Payment Contract checks that the pull payment has been singed by the customer of the account.
    /// If the pull payment doesn't have a trial period, the first execution will take place.
    /// The balance of the executor (msg.sender) is checked and if funding is needed 1 ETH is transferred.
    /// Emits 'LogPaymentRegistered' with customer address, beneficiary address and paymentID.
    /// @param v - recovery ID of the ETH signature. - https://github.com/ethereum/EIPs/issues/155
    /// @param r - R output of ECDSA signature.
    /// @param s - S output of ECDSA signature.
    /// @param _paymentDetails - all the relevant id-related details for the payment.
    /// @param _addresses - all the relevant addresses for the payment.
    /// @param _paymentAmounts - all the relevant amounts for the payment.
    /// @param _paymentTimestamps - all the relevant timestamps for the payment.
    /// @param _currency - currency of the payment / 3-letter abbr i.e. 'EUR'.
    function registerPullPayment(
        uint8 v,
        bytes32 r,
        bytes32 s,
        bytes32[4] memory _paymentDetails, // 0 paymentID, 1 businessID, 2 uniqueReferenceID, 3 paymentType
        address[3] memory _addresses, // 0 customer, 1 pull payment executor, 2 treasury
        uint256[3] memory _paymentAmounts, // 0 _initialConversionRate, 1 _fiatAmountInCents, 2 _initialPaymentAmountInCents
        uint256[4] memory _paymentTimestamps, // 0 _frequency, 1 _numberOfPayments, 2 _startTimestamp, 3 _trialPeriod
        string memory _currency
    )
    public
    isExecutor()
    isValidPaymentType(_paymentDetails[3])
    {
        require(_paymentDetails[0].length > 0, "Payment ID is empty.");
        require(_paymentDetails[1].length > 0, "Business ID is empty.");
        require(_paymentDetails[2].length > 0, "Unique Reference ID is empty.");

        require(_addresses[0] != address(0), "Customer Address is ZERO_ADDRESS.");
        require(_addresses[1] != address(0), "Beneficiary Address is ZERO_ADDRESS.");
        require(_addresses[2] != address(0), "Treasury Address is ZERO_ADDRESS.");

        require(_paymentAmounts[0] > 0, "Initial conversion rate is zero.");
        require(_paymentAmounts[1] > 0, "Payment amount in fiat is zero.");
        require(_paymentTimestamps[0] > 0, "Payment frequency is zero.");
        require(_paymentTimestamps[1] > 0, "Payment number of payments is zero.");
        require(_paymentTimestamps[2] > 0, "Payment start time is zero.");

        require(_paymentAmounts[0] < OVERFLOW_LIMITER_NUMBER, "Initial conversion rate is higher thant the overflow limit.");
        require(_paymentAmounts[1] < OVERFLOW_LIMITER_NUMBER, "Payment amount in fiat is higher thant the overflow limit.");
        require(_paymentAmounts[2] < OVERFLOW_LIMITER_NUMBER, "Payment initial amount in fiat is higher thant the overflow limit.");
        require(_paymentTimestamps[0] < OVERFLOW_LIMITER_NUMBER, "Payment frequency is higher thant the overflow limit.");
        require(_paymentTimestamps[1] < OVERFLOW_LIMITER_NUMBER, "Payment number of payments is higher thant the overflow limit.");
        require(_paymentTimestamps[2] < OVERFLOW_LIMITER_NUMBER, "Payment start time is higher thant the overflow limit.");
        require(_paymentTimestamps[3] < OVERFLOW_LIMITER_NUMBER, "Payment trial period is higher thant the overflow limit.");

        require(bytes(_currency).length > 0, "Currency is empty");

        pullPayments[_addresses[0]][_addresses[1]].paymentIds[0] = _paymentDetails[0];
        pullPayments[_addresses[0]][_addresses[1]].paymentType = _paymentDetails[3];

        pullPayments[_addresses[0]][_addresses[1]].treasuryAddress = _addresses[2];

        pullPayments[_addresses[0]][_addresses[1]].initialConversionRate = _paymentAmounts[0];
        pullPayments[_addresses[0]][_addresses[1]].fiatAmountInCents = _paymentAmounts[1];
        pullPayments[_addresses[0]][_addresses[1]].initialPaymentAmountInCents = _paymentAmounts[2];

        pullPayments[_addresses[0]][_addresses[1]].frequency = _paymentTimestamps[0];
        pullPayments[_addresses[0]][_addresses[1]].numberOfPayments = _paymentTimestamps[1];
        pullPayments[_addresses[0]][_addresses[1]].startTimestamp = _paymentTimestamps[2];
        pullPayments[_addresses[0]][_addresses[1]].trialPeriod = _paymentTimestamps[3];

        pullPayments[_addresses[0]][_addresses[1]].currency = _currency;

        require(isValidRegistration(
                v,
                r,
                s,
                _addresses[0],
                _addresses[1],
                pullPayments[_addresses[0]][_addresses[1]]),
            "Invalid pull payment registration - ECRECOVER_FAILED"
        );

        pullPayments[_addresses[0]][_addresses[1]].paymentIds[1] = _paymentDetails[1];
        pullPayments[_addresses[0]][_addresses[1]].paymentIds[2] = _paymentDetails[2];
        pullPayments[_addresses[0]][_addresses[1]].cancelTimestamp = 0;

        if (_paymentDetails[3] == TYPE_PULL_PAYMENT_WITH_FREE_TRIAL) {
            // nextPaymentTimestamp = startTimestamp + trialPeriod
            pullPayments[_addresses[0]][_addresses[1]].nextPaymentTimestamp = _paymentTimestamps[2] + _paymentTimestamps[3];
            pullPayments[_addresses[0]][_addresses[1]].lastPaymentTimestamp = 0;

        } else if (_paymentDetails[3] == TYPE_RECURRING_PULL_PAYMENT_WITH_INITIAL) {
            executePullPaymentOnRegistration(
                [_paymentDetails[0], _paymentDetails[1], _paymentDetails[2]], // 0 paymentID, 1 businessID, 2 uniqueReferenceID
                [_addresses[0], _addresses[2]], // 0 Customer Address, 1 Treasury Address
                [_paymentAmounts[2], _paymentAmounts[0]] // 0 initialPaymentAmountInCents, 1 initialConversionRate
            );
            pullPayments[_addresses[0]][_addresses[1]].lastPaymentTimestamp = now;
            //  nextPaymentTimestamp = startTimestamp + frequency
            pullPayments[_addresses[0]][_addresses[1]].nextPaymentTimestamp = _paymentTimestamps[2] + _paymentTimestamps[0];

        } else if (_paymentDetails[3] == TYPE_PULL_PAYMENT_WITH_PAID_TRIAL) {
            executePullPaymentOnRegistration(
                [_paymentDetails[0], _paymentDetails[1], _paymentDetails[2]], // paymentID , businessID , uniqueReferenceID
                [_addresses[0], _addresses[2]], // 0 Customer Address, 1 Treasury Address
                [_paymentAmounts[2], _paymentAmounts[0]] // 0 initialPaymentAmountInCents, 1 initialConversionRate
            );
            pullPayments[_addresses[0]][_addresses[1]].lastPaymentTimestamp = now;
            //  nextPaymentTimestamp = startTimestamp + trialPeriod
            pullPayments[_addresses[0]][_addresses[1]].nextPaymentTimestamp = _paymentTimestamps[2] + _paymentTimestamps[3];

        } else {
            executePullPaymentOnRegistration(
                [_paymentDetails[0], _paymentDetails[1], _paymentDetails[2]], // paymentID , businessID , uniqueReferenceID
                [_addresses[0], _addresses[2]], // Customer Address, Treasury Address
                [_paymentAmounts[1], _paymentAmounts[0]] // fiatAmountInCents, initialConversionRate
            );

            pullPayments[_addresses[0]][_addresses[1]].lastPaymentTimestamp = now;
            //  nextPaymentTimestamp = startTimestamp + frequency
            pullPayments[_addresses[0]][_addresses[1]].nextPaymentTimestamp = _paymentTimestamps[2] + _paymentTimestamps[0];
            //  numberOfPayments = numberOfPayments - 1
            pullPayments[_addresses[0]][_addresses[1]].numberOfPayments = _paymentTimestamps[1] - 1;
        }

        if (isFundingNeeded(msg.sender)) {
            msg.sender.transfer(FUNDING_AMOUNT);
        }

        emit LogPaymentRegistered(_addresses[0], _paymentDetails[0], _paymentDetails[1], _paymentDetails[2]);
    }

    /// @dev Deletes a pull payment for a beneficiary - The deletion needs can be executed only by one of the
    /// executors of the PumaPay Pull Payment Contract
    /// and the PumaPay Pull Payment Contract checks that the beneficiary and the paymentID have
    /// been singed by the customer of the account.
    /// This method sets the cancellation of the pull payment in the pull payments array for this beneficiary specified.
    /// The balance of the executor (msg.sender) is checked and if funding is needed 1 ETH is transferred.
    /// Emits 'LogPaymentCancelled' with beneficiary address and paymentID.
    /// @param v - recovery ID of the ETH signature. - https://github.com/ethereum/EIPs/issues/155
    /// @param r - R output of ECDSA signature.
    /// @param s - S output of ECDSA signature.
    /// @param _paymentID - ID of the payment.
    /// @param _customerAddress - customer address that is linked to this pull payment.
    /// @param _pullPaymentExecutor - address that is allowed to execute this pull payment.
    function deletePullPayment(
        uint8 v,
        bytes32 r,
        bytes32 s,
        bytes32 _paymentID,
        address _customerAddress,
        address _pullPaymentExecutor
    )
    public
    isExecutor()
    paymentExists(_customerAddress, _pullPaymentExecutor)
    paymentNotCancelled(_customerAddress, _pullPaymentExecutor)
    isValidDeletionRequest(_paymentID, _customerAddress, _pullPaymentExecutor)
    {
        require(isValidDeletion(v, r, s, _paymentID, _customerAddress, _pullPaymentExecutor), "Invalid deletion - ECRECOVER_FAILED.");

        pullPayments[_customerAddress][_pullPaymentExecutor].cancelTimestamp = now;

        if (isFundingNeeded(msg.sender)) {
            msg.sender.transfer(FUNDING_AMOUNT);
        }

        emit LogPaymentCancelled(
            _customerAddress,
            _paymentID,
            pullPayments[_customerAddress][_pullPaymentExecutor].paymentIds[1],
            pullPayments[_customerAddress][_pullPaymentExecutor].paymentIds[2]
        );
    }

    /// ===============================================================================================================
    ///                                      Public Functions
    /// ===============================================================================================================

    /// @dev Executes a pull payment for the msg.sender - The pull payment should exist and the payment request
    /// should be valid in terms of when it can be executed.
    /// Emits 'LogPullPaymentExecuted' with customer address, msg.sender as the beneficiary address and the paymentID.
    /// Use Case 1: Single/Recurring Fixed Pull Payment (initialPaymentAmountInCents == 0 )
    /// ------------------------------------------------
    /// We calculate the amount in PMA using the rate for the currency specified in the pull payment
    /// and the 'fiatAmountInCents' and we transfer from the customer account the amount in PMA.
    /// After execution we set the last payment timestamp to NOW, the next payment timestamp is incremented by
    /// the frequency and the number of payments is decreased by 1.
    /// Use Case 2: Recurring Fixed Pull Payment with initial fee (initialPaymentAmountInCents > 0)
    /// ------------------------------------------------------------------------------------------------
    /// We calculate the amount in PMA using the rate for the currency specified in the pull payment
    /// and the 'initialPaymentAmountInCents' and we transfer from the customer account the amount in PMA.
    /// After execution we set the last payment timestamp to NOW and the 'initialPaymentAmountInCents to ZERO.
    /// @param _customerAddress - address of the customer from which the msg.sender requires to pull funds.
    /// @param _paymentID - ID of the payment.
    /// @param _conversionRate - conversion rate with which the payment needs to take place
    function executePullPayment(address _customerAddress, bytes32 _paymentID, uint256 _conversionRate)
    public
    paymentExists(_customerAddress, msg.sender)
    isValidPullPaymentExecutionRequest(_customerAddress, msg.sender, _paymentID)
    validAmount(_conversionRate)
    returns (bool)
    {
        uint256 conversionRate = _conversionRate;
        address customerAddress = _customerAddress;
        bytes32[3] memory paymentIds = pullPayments[customerAddress][msg.sender].paymentIds;
        address treasury = pullPayments[customerAddress][msg.sender].treasuryAddress;

        uint256 amountInPMA = calculatePMAFromFiat(pullPayments[customerAddress][msg.sender].fiatAmountInCents, _conversionRate);

        pullPayments[customerAddress][msg.sender].nextPaymentTimestamp =
        pullPayments[customerAddress][msg.sender].nextPaymentTimestamp + pullPayments[customerAddress][msg.sender].frequency;

        pullPayments[customerAddress][msg.sender].numberOfPayments = pullPayments[customerAddress][msg.sender].numberOfPayments - 1;
        pullPayments[customerAddress][msg.sender].lastPaymentTimestamp = now;

        token.transferFrom(
            customerAddress,
            treasury,
            amountInPMA
        );

        emit LogPullPaymentExecuted(
            customerAddress,
            paymentIds[0],
            paymentIds[1],
            paymentIds[2],
            amountInPMA,
            conversionRate
        );

        return true;
    }

    /// ===============================================================================================================
    ///                                      Internal Functions
    /// ===============================================================================================================

    function executePullPaymentOnRegistration(
        bytes32[3] memory _paymentDetails, // 0 paymentID, 1 businessID, 2 uniqueReferenceID
        address[2] memory _addresses, // 0 customer Address, 1 treasury Address
        uint256[2] memory _paymentAmounts // 0 _fiatAmountInCents, 1 _conversionRate
    )
    internal
    returns (bool) {
        uint256 amountInPMA = calculatePMAFromFiat(_paymentAmounts[0], _paymentAmounts[1]);
        token.transferFrom(_addresses[0], _addresses[1], amountInPMA);

        emit LogPullPaymentExecuted(
            _addresses[0],
            _paymentDetails[0],
            _paymentDetails[1],
            _paymentDetails[2],
            amountInPMA,
            _paymentAmounts[1]
        );

        return true;
    }

    /// @dev Calculates the PMA Rate for the fiat currency specified - The rate is set every 10 minutes by our PMA server
    /// for the currencies specified in the smart contract.
    /// @param _fiatAmountInCents - payment amount in fiat CENTS so that is always integer
    /// @param _conversionRate - conversion rate with which the payment needs to take place
    /// RATE CALCULATION EXAMPLE
    /// ------------------------
    /// RATE ==> 1 PMA = 0.01 USD$
    /// 1 USD$ = 1/0.01 PMA = 100 PMA
    /// Start the calculation from one ether - PMA Token has 18 decimals
    /// Multiply by the DECIMAL_FIXER (1e+10) to fix the multiplication of the rate
    /// Multiply with the fiat amount in cents
    /// Divide by the Rate of PMA to Fiat in cents
    /// Divide by the FIAT_TO_CENT_FIXER to fix the _fiatAmountInCents
    function calculatePMAFromFiat(uint256 _fiatAmountInCents, uint256 _conversionRate)
    internal
    pure
    validAmount(_fiatAmountInCents)
    validAmount(_conversionRate)
    returns (uint256) {
        return ONE_ETHER.mul(DECIMAL_FIXER).mul(_fiatAmountInCents).div(_conversionRate).div(FIAT_TO_CENT_FIXER);
    }

    /// @dev Checks if a registration request is valid by comparing the v, r, s params
    /// and the hashed params with the customer address.
    /// @param v - recovery ID of the ETH signature. - https://github.com/ethereum/EIPs/issues/155
    /// @param r - R output of ECDSA signature.
    /// @param s - S output of ECDSA signature.
    /// @param _customerAddress - customer address that is linked to this pull payment.
    /// @param _pullPaymentExecutor - address that is allowed to execute this pull payment.
    /// @param _pullPayment - pull payment to be validated.
    /// @return bool - if the v, r, s params with the hashed params match the customer address
    function isValidRegistration(
        uint8 v,
        bytes32 r,
        bytes32 s,
        address _customerAddress,
        address _pullPaymentExecutor,
        PullPayment memory _pullPayment
    )
    internal
    pure
    returns (bool)
    {
        return ecrecover(
            keccak256(
                abi.encodePacked(
                    _pullPaymentExecutor,
                    _pullPayment.paymentIds[0],
                    _pullPayment.paymentType,
                    _pullPayment.treasuryAddress,
                    _pullPayment.currency,
                    _pullPayment.initialPaymentAmountInCents,
                    _pullPayment.fiatAmountInCents,
                    _pullPayment.frequency,
                    _pullPayment.numberOfPayments,
                    _pullPayment.startTimestamp,
                    _pullPayment.trialPeriod
                )
            ),
            v, r, s) == _customerAddress;
    }

    /// @dev Checks if a deletion request is valid by comparing the v, r, s params
    /// and the hashed params with the customer address.
    /// @param v - recovery ID of the ETH signature. - https://github.com/ethereum/EIPs/issues/155
    /// @param r - R output of ECDSA signature.
    /// @param s - S output of ECDSA signature.
    /// @param _paymentID - ID of the payment.
    /// @param _customerAddress - customer address that is linked to this pull payment.
    /// @param _pullPaymentExecutor - address that is allowed to execute this pull payment.
    /// @return bool - if the v, r, s params with the hashed params match the customer address
    function isValidDeletion(
        uint8 v,
        bytes32 r,
        bytes32 s,
        bytes32 _paymentID,
        address _customerAddress,
        address _pullPaymentExecutor
    )
    internal
    view
    returns (bool)
    {
        return ecrecover(
            keccak256(
                abi.encodePacked(
                    _paymentID,
                    _pullPaymentExecutor
                )
            ), v, r, s) == _customerAddress
        && keccak256(
            abi.encodePacked(pullPayments[_customerAddress][_pullPaymentExecutor].paymentIds[0])
        ) == keccak256(abi.encodePacked(_paymentID)
        );
    }

    /// @dev Checks if a payment for a beneficiary of a customer exists.
    /// @param _customerAddress - customer address that is linked to this pull payment.
    /// @param _pullPaymentExecutor - address to execute a pull payment.
    /// @return bool - whether the beneficiary for this customer has a pull payment to execute.
    function doesPaymentExist(address _customerAddress, address _pullPaymentExecutor)
    internal
    view
    returns (bool) {
        return (
        bytes(pullPayments[_customerAddress][_pullPaymentExecutor].currency).length > 0 &&
        pullPayments[_customerAddress][_pullPaymentExecutor].fiatAmountInCents > 0 &&
        pullPayments[_customerAddress][_pullPaymentExecutor].frequency > 0 &&
        pullPayments[_customerAddress][_pullPaymentExecutor].startTimestamp > 0 &&
        pullPayments[_customerAddress][_pullPaymentExecutor].numberOfPayments > 0 &&
        pullPayments[_customerAddress][_pullPaymentExecutor].nextPaymentTimestamp > 0
        );
    }

    /// @dev Checks if the address of an owner/executor needs to be funded.
    /// The minimum amount the owner/executors should always have is 0.001 ETH
    /// @param _address - address of owner/executors that the balance is checked against.
    /// @return bool - whether the address needs more ETH.
    function isFundingNeeded(address _address)
    private
    view
    returns (bool) {
        return address(_address).balance <= MINIMUM_AMOUNT_OF_ETH_FOR_OPERATORS;
    }
}
