// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./interfaces/IERC20Extended.sol";
import "./interfaces/ILockManager.sol";
import "./lib/Initializable.sol";

/**
 * @title EdenNetwork
 * @dev It is VERY IMPORTANT that modifications to this contract do not change the storage layout of the existing variables.  
 * Be especially careful when importing any external contracts/libraries.
 * If you do not know what any of this means, BACK AWAY FROM THE CODE NOW!!
 */
contract EdenNetwork is Initializable {

    /// @notice Slot bid details
    struct Bid {
        address bidder;
        uint16 taxNumerator;
        uint16 taxDenominator;
        uint64 periodStart;
        uint128 bidAmount;
    }

    /// @notice Expiration timestamp of current bid for specified slot index
    mapping (uint8 => uint64) public slotExpiration;
    
    /// @dev Address to be prioritized for given slot
    mapping (uint8 => address) private _slotDelegate;

    /// @dev Address that owns a given slot and is able to set the slot delegate
    mapping (uint8 => address) private _slotOwner;

    /// @notice Current bid for given slot
    mapping (uint8 => Bid) public slotBid;

    /// @notice Staked balance in contract
    mapping (address => uint128) public stakedBalance;

    /// @notice Balance in contract that was previously used for bid
    mapping (address => uint128) public lockedBalance;

    /// @notice Token used to reserve slot
    IERC20Extended public token;

    /// @notice Lock Manager contract
    ILockManager public lockManager;

    /// @notice Admin that can set the contract tax rate
    address public admin;

    /// @notice Numerator for tax rate
    uint16 public taxNumerator;

    /// @notice Denominator for tax rate
    uint16 public taxDenominator;

    /// @notice Minimum bid to reserve slot
    uint128 public MIN_BID;

    /// @dev Reentrancy var used like bool, but with refunds
    uint256 private _NOT_ENTERED;

    /// @dev Reentrancy var used like bool, but with refunds
    uint256 private _ENTERED;

    /// @dev Reentrancy status
    uint256 private _status;

    /// @notice Only admin can call
    modifier onlyAdmin() {
        require(msg.sender == admin, "not admin");
        _;
    }

    /// @notice Only slot owner can call
    modifier onlySlotOwner(uint8 slot) {
        require(msg.sender == slotOwner(slot), "not slot owner");
        _;
    }

    /// @notice Reentrancy prevention
    modifier nonReentrant() {
        // On the first call to nonReentrant, _notEntered will be true
        require(_status != _ENTERED, "reentrant call");

        // Any calls to nonReentrant after this point will fail
        _status = _ENTERED;

        _;

        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _status = _NOT_ENTERED;
    }

    /// @notice Event emitted when admin is updated
    event AdminUpdated(address indexed newAdmin, address indexed oldAdmin);

    /// @notice Event emitted when the tax rate is updated
    event TaxRateUpdated(uint16 newNumerator, uint16 newDenominator, uint16 oldNumerator, uint16 oldDenominator);

    /// @notice Event emitted when slot is claimed
    event SlotClaimed(uint8 indexed slot, address indexed owner, address indexed delegate, uint128 newBidAmount, uint128 oldBidAmount, uint16 taxNumerator, uint16 taxDenominator);
    
    /// @notice Event emitted when slot delegate is updated
    event SlotDelegateUpdated(uint8 indexed slot, address indexed owner, address indexed newDelegate, address oldDelegate);

    /// @notice Event emitted when a user stakes tokens
    event Stake(address indexed staker, uint256 stakeAmount);

    /// @notice Event emitted when a user unstakes tokens
    event Unstake(address indexed staker, uint256 unstakedAmount);

    /// @notice Event emitted when a user withdraws locked tokens
    event Withdraw(address indexed withdrawer, uint256 withdrawalAmount);

    /**
     * @notice Initialize EdenNetwork contract
     * @param _token Token address
     * @param _lockManager Lock Manager address
     * @param _admin Admin address
     * @param _taxNumerator Numerator for tax rate
     * @param _taxDenominator Denominator for tax rate
     */
    function initialize(
        IERC20Extended _token,
        ILockManager _lockManager,
        address _admin,
        uint16 _taxNumerator,
        uint16 _taxDenominator
    ) public initializer {
        token = _token;
        lockManager = _lockManager;
        admin = _admin;
        emit AdminUpdated(_admin, address(0));

        taxNumerator = _taxNumerator;
        taxDenominator = _taxDenominator;
        emit TaxRateUpdated(_taxNumerator, _taxDenominator, 0, 0);

        MIN_BID = 10000000000000000;
        _NOT_ENTERED = 1;
        _ENTERED = 2;
        _status = _NOT_ENTERED;
    }

    /**
     * @notice Get current owner of slot
     * @param slot Slot index
     * @return Slot owner address
     */
    function slotOwner(uint8 slot) public view returns (address) {
        if(slotForeclosed(slot)) {
            return address(0);
        }
        return _slotOwner[slot];
    }

    /**
     * @notice Get current slot delegate
     * @param slot Slot index
     * @return Slot delegate address
     */
    function slotDelegate(uint8 slot) public view returns (address) {
        if(slotForeclosed(slot)) {
            return address(0);
        }
        return _slotDelegate[slot];
    }

    /**
     * @notice Get current cost to claim slot
     * @param slot Slot index
     * @return Slot cost
     */
    function slotCost(uint8 slot) external view returns (uint128) {
        if(slotForeclosed(slot)) {
            return MIN_BID;
        }

        Bid memory currentBid = slotBid[slot];
        return currentBid.bidAmount * 110 / 100;
    }

    /**
     * @notice Claim slot
     * @param slot Slot index
     * @param bid Bid amount
     * @param delegate Delegate for slot
     */
    function claimSlot(
        uint8 slot, 
        uint128 bid, 
        address delegate
    ) external nonReentrant {
        _claimSlot(slot, bid, delegate);
    }

    /**
     * @notice Claim slot using permit for approval
     * @param slot Slot index
     * @param bid Bid amount
     * @param delegate Delegate for slot
     * @param deadline The time at which to expire the signature
     * @param v The recovery byte of the signature
     * @param r Half of the ECDSA signature pair
     * @param s Half of the ECDSA signature pair
     */
    function claimSlotWithPermit(
        uint8 slot, 
        uint128 bid, 
        address delegate, 
        uint256 deadline, 
        uint8 v, 
        bytes32 r, 
        bytes32 s
    ) external nonReentrant {
        token.permit(msg.sender, address(this), bid, deadline, v, r, s);
        _claimSlot(slot, bid, delegate);
    }

    /**
     * @notice Get untaxed balance for current slot bid
     * @param slot Slot index
     * @return balance Slot balance
     */
    function slotBalance(uint8 slot) public view returns (uint128 balance) {
        Bid memory currentBid = slotBid[slot];
        if (currentBid.bidAmount == 0 || slotForeclosed(slot)) {
            return 0;
        } else if (block.timestamp == currentBid.periodStart) {
            return currentBid.bidAmount;
        } else {
            return uint128(uint256(currentBid.bidAmount) - (uint256(currentBid.bidAmount) * (block.timestamp - currentBid.periodStart) * currentBid.taxNumerator / (uint256(currentBid.taxDenominator) * 86400)));
        }
    }

    /**
     * @notice Returns true if a given slot bid has expired
     * @param slot Slot index
     * @return True if slot is foreclosed
     */
    function slotForeclosed(uint8 slot) public view returns (bool) {
        if(slotExpiration[slot] <= block.timestamp) {
            return true;
        }
        return false;
    }

    /**
     * @notice Stake tokens
     * @param amount Amount of tokens to stake
     */
    function stake(uint128 amount) external nonReentrant {
        _stake(amount);
    }

    /**
     * @notice Stake tokens using permit for approval
     * @param amount Amount of tokens to stake
     * @param deadline The time at which to expire the signature
     * @param v The recovery byte of the signature
     * @param r Half of the ECDSA signature pair
     * @param s Half of the ECDSA signature pair
     */
    function stakeWithPermit(
        uint128 amount, 
        uint256 deadline, 
        uint8 v, 
        bytes32 r, 
        bytes32 s
    ) external nonReentrant {
        token.permit(msg.sender, address(this), amount, deadline, v, r, s);
        _stake(amount);
    }

    /**
     * @notice Unstake tokens
     * @param amount Amount of tokens to unstake
     */
    function unstake(uint128 amount) external nonReentrant {
        require(stakedBalance[msg.sender] >= amount, "amount > unlocked balance");
        lockManager.removeVotingPower(msg.sender, address(token), amount);
        stakedBalance[msg.sender] -= amount;
        token.transfer(msg.sender, amount);
        emit Unstake(msg.sender, amount);
    }

    /**
     * @notice Withdraw locked tokens
     * @param amount Amount of tokens to withdraw
     */
    function withdraw(uint128 amount) external nonReentrant {
        require(lockedBalance[msg.sender] >= amount, "amount > unlocked balance");
        lockedBalance[msg.sender] -= amount;
        token.transfer(msg.sender, amount);
        emit Withdraw(msg.sender, amount);
    }

    /**
     * @notice Allows slot owners to set a new slot delegate
     * @param slot Slot index
     * @param delegate Delegate address
     */
    function setSlotDelegate(uint8 slot, address delegate) external onlySlotOwner(slot) {
        require(delegate != address(0), "cannot delegate to 0 address");
        emit SlotDelegateUpdated(slot, msg.sender, delegate, slotDelegate(slot));
        _slotDelegate[slot] = delegate;
    }

    /**
     * @notice Set new tax rate
     * @param numerator New tax numerator
     * @param denominator New tax denominator
     */
    function setTaxRate(uint16 numerator, uint16 denominator) external onlyAdmin {
        require(denominator > numerator, "denominator must be > numerator");
        emit TaxRateUpdated(numerator, denominator, taxNumerator, taxDenominator);
        taxNumerator = numerator;
        taxDenominator = denominator;
    }

    /**
     * @notice Set new admin
     * @param newAdmin Nex admin address
     */
    function setAdmin(address newAdmin) external onlyAdmin {
        emit AdminUpdated(newAdmin, admin);
        admin = newAdmin;
    }

    /**
     * @notice Internal implementation of claimSlot
     * @param slot Slot index
     * @param bid Bid amount
     * @param delegate Delegate address
     */
    function _claimSlot(uint8 slot, uint128 bid, address delegate) internal {
        require(delegate != address(0), "cannot delegate to 0 address");
        Bid storage currentBid = slotBid[slot];
        uint128 existingBidAmount = currentBid.bidAmount;
        uint128 existingSlotBalance = slotBalance(slot);
        uint128 taxedBalance = existingBidAmount - existingSlotBalance;
        require((existingSlotBalance == 0 && bid >= MIN_BID) || bid >= existingBidAmount * 110 / 100, "bid too small");

        uint128 bidderLockedBalance = lockedBalance[msg.sender];
        uint128 bidIncrement = currentBid.bidder == msg.sender ? bid - existingSlotBalance : bid;
        if (bidderLockedBalance > 0) {
            if (bidderLockedBalance >= bidIncrement) {
                lockedBalance[msg.sender] -= bidIncrement;
            } else {
                lockedBalance[msg.sender] = 0;
                token.transferFrom(msg.sender, address(this), bidIncrement - bidderLockedBalance);
            }
        } else {
            token.transferFrom(msg.sender, address(this), bidIncrement);
        }

        if (currentBid.bidder != msg.sender) {
            lockedBalance[currentBid.bidder] += existingSlotBalance;
        }
        
        if (taxedBalance > 0) {
            token.burn(taxedBalance);
        }

        _slotOwner[slot] = msg.sender;
        _slotDelegate[slot] = delegate;

        currentBid.bidder = msg.sender;
        currentBid.periodStart = uint64(block.timestamp);
        currentBid.bidAmount = bid;
        currentBid.taxNumerator = taxNumerator;
        currentBid.taxDenominator = taxDenominator;

        slotExpiration[slot] = uint64(block.timestamp + uint256(taxDenominator) * 86400 / uint256(taxNumerator));

        emit SlotClaimed(slot, msg.sender, delegate, bid, existingBidAmount, taxNumerator, taxDenominator);
    }

    /**
     * @notice Internal implementation of stake
     * @param amount Amount of tokens to stake
     */
    function _stake(uint128 amount) internal {
        token.transferFrom(msg.sender, address(this), amount);
        lockManager.grantVotingPower(msg.sender, address(token), amount);
        stakedBalance[msg.sender] += amount;
        emit Stake(msg.sender, amount);
    }
}