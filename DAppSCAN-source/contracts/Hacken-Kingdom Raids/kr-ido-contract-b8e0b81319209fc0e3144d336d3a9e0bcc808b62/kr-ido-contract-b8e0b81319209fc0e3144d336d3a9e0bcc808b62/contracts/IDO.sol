// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract IDO is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20Metadata;

    // Info of each investor
    struct DepositInfo {
        uint256 amount; // Total spent amount
        bool redeem; // Redeem status
    }

    // Start sale time
    uint256 public startSaleAt;
    // End sale time
    uint256 public endSaleAt;
    // Start grace time
    uint256 public startGraceAt;
    // End grace time
    uint256 public endGraceAt;
    // Start redeem time
    uint256 public startRedeemAt;
    // End redeem time
    uint256 public endRedeemAt;
    // Total supply
    uint256 public totalSupply;
    // Min deposit
    uint256 public minDeposit;
    // Total deposit
    uint256 public totalDeposit;
    // Number of participants
    uint256 public numberParticipants;

    // Token for sale
    IERC20Metadata public token;
    // Token used to buy
    IERC20Metadata public currency;

    // Info of each investor that buy tokens.
    mapping(address => DepositInfo) public depositInfos;

    event Deposit(address indexed _user, uint256 _amount);
    event Withdraw(address indexed _user, uint256 _amount);
    event Redeem(address indexed _user, uint256 _amount);
    event Finalize(address indexed _user, uint256 _amount);
    event RescureNonRedeem(address indexed _user, uint256 _amount);

    constructor(
        address _token,
        address _currency,
        uint256 _startSaleAt,
        uint256 _endSaleAt,
        uint256 _startGraceAt,
        uint256 _endGraceAt,
        uint256 _startRedeemAt,
        uint256 _endRedeemAt,
        uint256 _totalSupply,
        uint256 _minDeposit
    ) {
        require(_token != address(0), "Invalid token address");
        require(_currency != address(0), "Invalid currency address");
        require(_startSaleAt < _endSaleAt, "_startSaleAt must be < _endSaleAt");
        require(
            _endSaleAt <= _startGraceAt,
            "_endSaleAt must be <= _startGraceAt"
        );
        require(
            _startGraceAt < _endGraceAt,
            "_startGraceAt must be < _endGraceAt"
        );
        require(
            _endGraceAt <= _startRedeemAt,
            "_endGraceAt must be <= _startRedeemAt"
        );
        require(
            _startRedeemAt < _endRedeemAt,
            "_startRedeemAt must be <= _endRedeemAt"
        );
        require(_totalSupply > 0, "_totalSupply must be > 0");
        require(_minDeposit > 0, "_minDeposit must be > 0");

        token = IERC20Metadata(_token);
        currency = IERC20Metadata(_currency);
        startSaleAt = _startSaleAt;
        endSaleAt = _endSaleAt;
        startGraceAt = _startGraceAt;
        endGraceAt = _endGraceAt;
        startRedeemAt = _startRedeemAt;
        endRedeemAt = _endRedeemAt;
        totalSupply = _totalSupply;
        minDeposit = _minDeposit;
    }

    function getCurrentPrice() external view returns (uint256) {
        uint8 tokenDecimals = token.decimals();
        return (totalDeposit * (10**tokenDecimals)) / totalSupply;
    }

    // User's first deposit required amount >= minDeposit
    // There is not limitation from next time
    function deposit(uint256 _amount) external salePhaseActive nonReentrant {
        DepositInfo storage userDeposit = depositInfos[msg.sender];
        uint256 userTotalDeposit = userDeposit.amount;
        if (userTotalDeposit == 0) {
            require(_amount >= minDeposit, "Amount must be >= minDeposit");
        } else {
            require(_amount > 0, "Amount must be > 0");
        }
        currency.safeTransferFrom(msg.sender, address(this), _amount);
        totalDeposit = totalDeposit + _amount;
        if (userTotalDeposit == 0) {
            numberParticipants = numberParticipants + 1;
        }
        userTotalDeposit = userTotalDeposit + _amount;
        userDeposit.amount = userTotalDeposit;
        emit Deposit(msg.sender, _amount);
    }

    // Get redeemable tokens by address
    function redeemable(address _address) public view returns (uint256) {
        if (
            totalDeposit > 0 &&
            depositInfos[_address].amount > 0 &&
            !depositInfos[_address].redeem
        ) {
            uint256 redeemableTokens = (depositInfos[_address].amount *
                totalSupply) / totalDeposit;
            return redeemableTokens;
        } else {
            return 0;
        }
    }

    // Users can withdraw their deposits before grace phase end
    function withdraw() external allowWithdrawal nonReentrant {
        DepositInfo storage userDeposit = depositInfos[msg.sender];
        uint256 userTotalDeposit = userDeposit.amount;
        require(userTotalDeposit > 0, "Invalid action");
        userDeposit.amount = 0;
        totalDeposit = totalDeposit - userTotalDeposit;
        numberParticipants = numberParticipants - 1;
        currency.safeTransfer(msg.sender, userTotalDeposit);
        emit Withdraw(msg.sender, userTotalDeposit);
    }

    function redeem() external redeemPhaseActive nonReentrant {
        uint256 redeemableValue = redeemable(msg.sender);
        require(redeemableValue > 0, "Insufficient redeem amount");
        DepositInfo storage userDeposit = depositInfos[msg.sender];
        userDeposit.redeem = true;
        token.safeTransfer(msg.sender, redeemableValue);
        emit Redeem(msg.sender, redeemableValue);
    }

    function finalize() external onlyOwner gracePhaseEnded nonReentrant {
        uint256 currencyBalance = currency.balanceOf(address(this));
        currency.safeTransfer(msg.sender, currencyBalance);
        emit Finalize(msg.sender, currencyBalance);
    }

    function rescureNonRedeemTokens()
        external
        onlyOwner
        redeemPhaseEnded
        nonReentrant
    {
        uint256 tokenBalance = token.balanceOf(address(this));
        token.safeTransfer(msg.sender, tokenBalance);
        emit RescureNonRedeem(msg.sender, tokenBalance);
    }

    function getPoolConfig()
        external
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        return (
            startSaleAt,
            endSaleAt,
            startGraceAt,
            endGraceAt,
            startRedeemAt,
            endRedeemAt,
            minDeposit
        );
    }

    modifier salePhaseActive() {
        require(
            startSaleAt <= block.timestamp && block.timestamp <= endSaleAt,
            "Not in sale phase"
        );
        _;
    }

    modifier allowWithdrawal() {
        require(
            (startSaleAt <= block.timestamp && block.timestamp <= endSaleAt) ||
                (startGraceAt <= block.timestamp &&
                    block.timestamp <= endGraceAt),
            "Can't withdraw"
        );
        _;
    }

    modifier redeemPhaseActive() {
        require(
            startRedeemAt <= block.timestamp && block.timestamp <= endRedeemAt,
            "Not in redeem phase"
        );
        _;
    }

    modifier gracePhaseEnded() {
        require(block.timestamp > endGraceAt, "Grace is not end");
        _;
    }

    modifier redeemPhaseEnded() {
        require(block.timestamp > endRedeemAt, "Redeem is not end");
        _;
    }
}
