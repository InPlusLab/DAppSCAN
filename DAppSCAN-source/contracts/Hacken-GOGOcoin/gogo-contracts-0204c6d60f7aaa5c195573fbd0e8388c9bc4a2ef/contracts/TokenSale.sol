// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract TokenSale is Ownable, ReentrancyGuard {
    uint256 public maticPrice;
    uint256 public usdcPrice;
    uint256 public maxBuyAmount;
    uint256 public immutable cap;
    IERC20 immutable TokenContract;
    uint256 public tokensSold;
    address usdcAddress = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;
    uint256 public immutable releaseTime;
    uint256 public immutable unlockTime;
    bool public refundable = false;
    uint256 immutable multiplier = 30;

    struct PurchasedAmount {
        uint256 maticAmount;
        uint256 maticInvested;
        uint256 usdcAmount;
        uint256 usdcInvested;
    }

    struct LockedAmount {
        uint256 maticAmount;
        uint256 usdcAmount;
    }

    mapping(address => PurchasedAmount) public purchasedAmount;
    mapping(address => LockedAmount) public lockedAmount;

    event Sold(address indexed buyer, uint256 amount, bool isNative);

    constructor(
        IERC20 _saleToken,
        uint256 _maticPrice,
        uint256 _usdcPrice,
        uint256 _maxBuyAmount,
        uint256 _cap,
        uint256 _releaseTime,
        uint256 _unlockTime
    ) {
        maticPrice = _maticPrice;
        usdcPrice = _usdcPrice;
        maxBuyAmount = _maxBuyAmount;
        cap = _cap;
        releaseTime = _releaseTime;
        unlockTime = _unlockTime;
        TokenContract = _saleToken;
    }

    function setMaticPrice(uint256 _maticPrice) external onlyOwner {
        maticPrice = _maticPrice;
    }

    function setUSDCPrice(uint256 _usdcPrice) external onlyOwner {
        usdcPrice = _usdcPrice;
    }

    function setMaxBuyAmount(uint256 _maxBuyAmount) external onlyOwner {
        maxBuyAmount = _maxBuyAmount;
    }

    function buy(uint256 _buyAmount) external payable {
        require(
            releaseTime >= block.timestamp,
            "Cannot buy after the sale end"
        );
        require(
            tokensSold + _buyAmount <= cap,
            "Cannot buy that exceeds the cap"
        );
        require(
            msg.value == (maticPrice * _buyAmount) / 1e4 && msg.value != 0,
            "Incorrect pay amount"
        );
        PurchasedAmount storage allocation = purchasedAmount[msg.sender];

        allocation.maticAmount += (_buyAmount * multiplier) / 100;
        allocation.maticInvested += msg.value;

        LockedAmount storage allocationLocked = lockedAmount[msg.sender];

        allocationLocked.maticAmount += (_buyAmount * (100 - multiplier)) / 100;

        require(
            allocation.maticAmount +
                allocation.usdcAmount +
                allocationLocked.maticAmount +
                allocationLocked.usdcAmount <=
                maxBuyAmount
        );
        tokensSold += _buyAmount;

        emit Sold(msg.sender, _buyAmount, true);
    }

    function buyByUSDC(uint256 _buyAmount) external virtual {
        require(
            releaseTime >= block.timestamp,
            "Cannot buy after the sale end"
        );
        require(
            tokensSold + _buyAmount <= cap,
            "Cannot buy that exceeds the cap"
        );
        PurchasedAmount storage allocation = purchasedAmount[msg.sender];
        uint256 amount;
        amount = (usdcPrice * _buyAmount) / 1e4 / 1e12; // GoGo token decimals - USDC token decimals
        require(amount > 0, "Min amount limit");
        require(
            IERC20(usdcAddress).transferFrom(msg.sender, address(this), amount),
            "TF: Check allowance"
        );

        allocation.usdcAmount += (_buyAmount * multiplier) / 100;

        LockedAmount storage allocationLocked = lockedAmount[msg.sender];

        allocationLocked.usdcAmount += (_buyAmount * (100 - multiplier)) / 100;
        allocation.usdcInvested += amount;

        require(
            allocation.maticAmount +
                allocation.usdcAmount +
                allocationLocked.maticAmount +
                allocationLocked.usdcAmount <=
                maxBuyAmount
        );

        tokensSold += _buyAmount;

        emit Sold(msg.sender, _buyAmount, false);
    }

    function claim() external nonReentrant {
        require(
            releaseTime < block.timestamp,
            "Cannot claim before the sale ends"
        );
        PurchasedAmount memory allocation = purchasedAmount[msg.sender];
        uint256 totalAmount = allocation.usdcAmount + allocation.maticAmount;
        delete purchasedAmount[msg.sender];
        require(TokenContract.transfer(msg.sender, totalAmount));
    }

    function unLock() external nonReentrant {
        require(
            unlockTime < block.timestamp,
            "Cannot unlock before the unlock time"
        );
        LockedAmount storage allocationLocked = lockedAmount[msg.sender];
        uint256 totalAmount = allocationLocked.usdcAmount +
            allocationLocked.maticAmount;
        delete lockedAmount[msg.sender];
        require(TokenContract.transfer(msg.sender, totalAmount));
    }

    function getRefund() external nonReentrant {
        require(
            releaseTime < block.timestamp,
            "Cannot get refunded before the sale ends"
        );
        require(refundable, "Not possible to refund now");
        PurchasedAmount memory allocation = purchasedAmount[msg.sender];
        require(
            IERC20(usdcAddress).transfer(msg.sender, allocation.usdcInvested)
        );
        payable(msg.sender).transfer(allocation.maticInvested);
        delete purchasedAmount[msg.sender];
        delete lockedAmount[msg.sender];
    }

    function setRefundable(bool _flag) external onlyOwner {
        refundable = _flag;
    }

    function endSale() external onlyOwner {
        require(
            releaseTime < block.timestamp,
            "Cannot get fund back before the release time"
        );
        require(
            TokenContract.transfer(
                msg.sender,
                TokenContract.balanceOf(address(this))
            )
        );
        IERC20 usdc = IERC20(usdcAddress);
        usdc.transfer(msg.sender, usdc.balanceOf(address(this)));
        payable(msg.sender).transfer(address(this).balance);
    }
}
