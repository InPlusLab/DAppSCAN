// SPDX-License-Identifier: MIT
/// @dev size: 6.986 Kbytes
pragma solidity 0.8.4;

import { IERC20 } from "../ERC20/IERC20.sol";
import "../security/ReentrancyGuard.sol";
import "../utils/Counters.sol";
import "../utils/NonZeroAddressGuard.sol";
import "../security/Ownable.sol";


/// @title An instance to run vesting schedule for an organization
/// @notice Use this contract to create vesting schedule entires for team members
contract Vesting is ReentrancyGuard, Ownable, NonZeroAddressGuard {
    using Counters for Counters.Counter;

    /// @dev Counter for the number of entries in the vesting schedule.
    Counters.Counter private _entryIds;

    /// @notice ERC20 token we are vesting
    IERC20 public token;

    struct Entry {
        uint256 amount;
        uint256 start;
        uint256 end;
        uint256 cliff;
        uint256 lastUpdated;
        uint256 claimed;
        address recipient;
        bool isFireable;
        bool isFired;
    }

    /// @notice Mapping of vesting entries
    mapping(uint256 => Entry) public entries;

    /// @notice Mapping of addresses to lists of their entries IDs
    mapping(address => uint256[]) public entryIdsByRecipient;

    /// @dev Flag to prevent reinitialization
    bool private _initialized;

    event EntryCreated(uint256 indexed entryId, address recipient, uint256 amount, uint256 start, uint256 end, uint256 cliff);
    event EntryFired(uint256 indexed entryId);
    event Claimed(address indexed recipient, uint256 amount);

    /**
     * @notice Init a new vesting contract
     * @param owner_ owner of the contract
     * @param token_ address of the ERC20 token
     */
    function initialize(address owner_, IERC20 token_) external nonZeroAddress(owner_) nonZeroAddress(address(token_)) {
        require(!_initialized, "Already initialized");
        owner = owner_;
        token = token_;

        _initialized = true;
    }

    struct EntryVars {
        address recipient;
        uint256 amount;
        uint256 start;
        uint256 end;
        uint256 cliff;
        uint256 unlocked;
        bool isFireable;
    }

    /**
     * @notice Create new vesting entry
     * @notice A transfer made by AMPT Token holder is prior to bring tokens into the Vesting contract
     * @param entry beneficiary of the vested tokens
     * @return boolean indicating success
    */
    function createEntry(EntryVars calldata entry) external onlyOwner nonReentrant returns (bool){
        return _createEntry(entry);
    }

    /**
     * @notice Fire vesting entry
     * @param entryId ID of the fired entry
     * @return boolean indicating success
    */
    function fireEntry(uint256 entryId) external onlyOwner returns (bool){
        return _fireEntry(entryId);
    }

    /**
     * @notice Create new vesting entries in a batch
     * @notice A transfer made by AMPT Token holder is prior to bring tokens into the Vesting contract
     * @param _entries array of beneficiaries of the vested tokens
    */
    function createEntries(EntryVars[] calldata _entries) external onlyOwner nonReentrant returns (bool){
        require(_entries.length  > 0, "empty data");
        require(_entries.length  <= 80, "exceed max length");
//SWC-128-DoS With Block Gas Limit: L99, L111, L153, L180, L211
        for(uint8 i=0; i < _entries.length; i++) {
            _createEntry(_entries[i]);
        }
        return true;
    }

    /**
     * @notice Claim any vested tokens due
     * @dev Must be called directly by the beneficiary assigned the tokens in the entry
    */
    function claim() external nonReentrant  {
        uint256 totalAmount;
        for(uint8 i=0; i < entryIdsByRecipient[msg.sender].length; i++) {
            totalAmount += _claim(entryIdsByRecipient[msg.sender][i]);
        }
        if (totalAmount > 0) {
            emit Claimed(msg.sender, totalAmount);
            assert(token.transfer(msg.sender, totalAmount));
        }
    }

    /**
     * @notice Withdraw unused tokens
     * @dev Must be called directly by the beneficiary assigned the tokens in the entry
    */
    function withdraw(address destination) external onlyOwner nonZeroAddress(destination) returns (bool) {
        require(token.transfer(destination, this.balanceOf()), "transfer failed");
        return true;
    }

    /**
     * @notice Vested token balance for a beneficiary
     * @dev Must be called directly by the beneficiary assigned the tokens in the entry
     * @return _tokenBalance total balance proxied via the ERC20 token
    */
    function balanceOf() external view returns (uint256) {
        return token.balanceOf(address(this));
    }

    /**
     * @notice Currently available amount (based on the block timestamp)
     * @param entryId ID of the entry
     * @return amount tokens due from vesting entry
     */
    function balanceOf(uint256 entryId) external view returns (uint256 amount) {
        return _balanceOf(entryId);
    }

    /**
     * @notice Currently available amount (based on the block timestamp)
     * @param account beneficiary of the vested tokens
     * @return amount tokens due from vesting entry
     */
    function balanceOf(address account) external view returns (uint256 amount) {
        for(uint8 i=0; i < entryIdsByRecipient[account].length; i++) {
            amount += _balanceOf(entryIdsByRecipient[account][i]);
        }
        return amount;
    }



    struct Snapshot {
        uint256 entryId;
        uint256 amount;
        uint256 start;
        uint256 end;
        uint256 cliff;
        uint256 claimed;
        uint256 available;
        bool isFired;
    }

    /**
     * @notice Snapshot of the current state
     * @param account beneficiary of the vested tokens
     * @return snapshot of the current state
    */
    function getSnapshot(address account) external nonZeroAddress(account) view returns(Snapshot[] memory) {
        Snapshot[] memory snapshot = new Snapshot[](entryIdsByRecipient[account].length);

        for(uint8 i=0; i < entryIdsByRecipient[account].length; i++) {
            Entry memory entry = entries[entryIdsByRecipient[account][i]];
            snapshot[i] = Snapshot({
                entryId: entryIdsByRecipient[account][i],
                amount: entry.amount,
                start: entry.start,
                end: entry.end,
                cliff: entry.cliff,
                claimed: entry.claimed,
                available: _balanceOf(entryIdsByRecipient[account][i]),
                isFired: entry.isFired
            });
        }
        return snapshot;
    }

    /**
     * @notice Balance remaining in vesting entry
     * @param entryId ID of the entry
     * @return amount tokens still due (and currently locked) from vesting entry
    */
    function lockedOf(uint256 entryId) external view returns (uint256 amount) {
        return _lockedOf(entryId);
    }

    /**
     * @notice Balance remaining in vesting entry
     * @param account beneficiary of the vested tokens
     * @return amount tokens still due (and currently locked) from vesting entry
    */
    function lockedOf(address account) external view returns (uint256 amount) {
        for(uint8 i=0; i < entryIdsByRecipient[account].length; i++) {
            amount += _lockedOf(entryIdsByRecipient[account][i]);
        }
        return amount;
    }
//SWC-116-Block values as a proxy for time: L218
    function getBlockTimestamp() public virtual view returns (uint256) {
        return block.timestamp;
    }

    function _balanceOf(uint256 _entryId) internal view returns (uint256) {
        Entry storage entry = entries[_entryId];

        if (entry.amount == 0) { // entry not found
            return 0;
        }

        uint256 currentTimestamp = getBlockTimestamp();
        if (currentTimestamp <= entry.start + entry.cliff) {
            return 0;
        }

        if (currentTimestamp > entry.end || entry.isFired) {
            return entry.amount - entry.claimed;
        }

        uint256 vested = entry.amount * (currentTimestamp - entry.lastUpdated) / (entry.end - entry.start);
        return vested;
    }

    function _lockedOf(uint256 _entryId) internal view returns (uint256) {
        Entry storage entry = entries[_entryId];
        if (entry.amount == 0) { // entry not found
            return 0;
        }
        return entry.amount - entry.claimed;
    }

    function _createEntry(EntryVars memory entry) internal returns (bool success) {
        address recipient = entry.recipient;
        require(recipient != address(0), "recipient cannot be the zero address");


        require(entry.amount > 0, "amount must be greater than zero");
        require(entry.unlocked <= entry.amount, "unlocked cannot be greater than amount");
        require(entry.end >= entry.start, "End time must be after start time");
        require(entry.end > entry.start + entry.cliff, "cliff must be less than end");
        
        uint256 currentTimestamp = getBlockTimestamp();
        require(entry.start >= currentTimestamp, "Start time must be in the future");

        if (entry.unlocked > 0) {
            assert(token.transfer(recipient, entry.unlocked));
        }

        uint256 currentEntryId = _entryIds.current();
        if (entry.unlocked < entry.amount) {
            entries[currentEntryId] = Entry({
                recipient: recipient,
                amount: entry.amount - entry.unlocked,
                start: entry.start,
                lastUpdated: entry.start,
                end: entry.end,
                cliff: entry.cliff,
                claimed: 0,
                isFireable: entry.isFireable,
                isFired: false
            });
            entryIdsByRecipient[recipient].push(currentEntryId);

            emit EntryCreated(currentEntryId, recipient, entry.amount - entry.unlocked, entry.start, entry.end, entry.cliff);
            _entryIds.increment();
        }

        return true;
    }

    function _fireEntry(uint256 _entryId) internal returns (bool success) {
        Entry storage entry = entries[_entryId];
        require(entry.amount > 0, "entry not exists");
        require(entry.isFireable, "entry not fireable");

        entry.amount = _balanceOf(_entryId);
        entry.isFired = true;

        emit EntryFired(_entryId);
        return true;
    }

    function _claim(uint256 _entryId) internal returns (uint256 amount) {
        Entry storage entry = entries[_entryId];

        uint256 amountToClaim = _balanceOf(_entryId);
        if (amountToClaim > 0) {
            uint256 currentTimestamp = getBlockTimestamp();

            entry.lastUpdated = currentTimestamp;
            entry.claimed += amountToClaim;

            // Safety measure - this should never trigger
            require(entry.amount >= entry.claimed, "claim exceed vested amount");
        }

        return amountToClaim;
    }
}
