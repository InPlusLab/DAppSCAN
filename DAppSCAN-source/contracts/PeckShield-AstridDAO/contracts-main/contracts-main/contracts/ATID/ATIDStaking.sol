// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "../Dependencies/BaseMath.sol";
import "../Dependencies/IERC20.sol";
import "../Dependencies/SafeMath.sol";
import "../Dependencies/Ownable.sol";
import "../Dependencies/CheckContract.sol";
import "../Dependencies/console.sol";
import "../Dependencies/ReentrancyGuard.sol";
import "../Interfaces/IATIDToken.sol";
import "../Interfaces/IATIDStaking.sol";
import "../Dependencies/AstridMath.sol";
import "../Interfaces/IBAIToken.sol";
import "../Interfaces/IGovToken.sol";

// For multi-collateral support, there should be a separate ATIDStaking contract per collateral type.
contract ATIDStaking is IATIDStaking, Ownable, CheckContract, BaseMath, ReentrancyGuard {
    using SafeMath for uint;

    // --- Data ---
    string constant public NAME = "ATIDStaking";

    uint constant public SECONDS_IN_ONE_YEAR = 31536000; 
    uint[4] public WEIGHT_MULTIPLIERS;

    // TODO: Verify linked list implementation is correct.
    struct LockedStake {
        bool active;
        // Linked list structure.
        uint ID;
        uint prevID;  // 0 means current node is head.
        uint nextID;  // 0 means current node is tail.
        
        // Amount of ATID being locked here.
        uint amount;
        // Timestamp to reach before the locked stakes are available for unstaking.
        uint lockedUntil;
        // Multipliers to apply to the stake due to locking for a long enough time.
        uint stakeWeight;
    }

    mapping(address => mapping(uint => LockedStake)) public lockedStakeMap;
    mapping(address => uint) public headLockedStakeIDMap;
    mapping(address => uint) public tailLockedStakeIDMap;
    mapping(address => uint) public nextLockedStakeIDMap;
    mapping(address => uint) public weightedStakes;

    // mapping( address => uint) public stakes;
    uint public totalWeightedATIDStaked;

    // The following two fields are just for frontend querying.
    // Do not use them for accounting.
    mapping(address => uint) public unweightedStakes;
    uint public totalUnweightedATIDStaked;

    uint public F_COL;  // Running sum of collateral fees per-ATID-staked
    uint public F_BAI; // Running sum of ATID fees per-ATID-staked

    // User snapshots of F_COL and F_BAI, taken at the point at which their latest deposit was made
    mapping (address => Snapshot) public snapshots; 

    struct Snapshot {
        uint F_COL_Snapshot;
        uint F_BAI_Snapshot;
    }
    
    IATIDToken public atidToken;
    IERC20 public colToken;
    IBAIToken public baiToken;

    // TODO(Astrid): check this.
    IGovToken public govToken;

    address public vaultManagerAddress;
    address public borrowerOperationsAddress;
    address public activePoolAddress;

    // --- Functions ---
    constructor() Ownable() {
        // Exponential gain, up to > 3 years.
        WEIGHT_MULTIPLIERS = [1, 2, 4, 8];
    }

    function setAddresses
    (
        address _atidTokenAddress,
        address _baiTokenAddress,
        address _colTokenAddress,
        address _vaultManagerAddress, 
        address _borrowerOperationsAddress,
        address _activePoolAddress,
        address _govTokenAddress
    ) 
        external 
        onlyOwner 
        override 
    {
        checkContract(_atidTokenAddress);
        checkContract(_baiTokenAddress);
        checkContract(_colTokenAddress);
        checkContract(_vaultManagerAddress);
        checkContract(_borrowerOperationsAddress);
        checkContract(_activePoolAddress);
        checkContract(_govTokenAddress);

        atidToken = IATIDToken(_atidTokenAddress);
        baiToken = IBAIToken(_baiTokenAddress);
        colToken = IERC20(_colTokenAddress);
        vaultManagerAddress = _vaultManagerAddress;
        borrowerOperationsAddress = _borrowerOperationsAddress;
        activePoolAddress = _activePoolAddress;
        govToken = IGovToken(_govTokenAddress);

        emit ATIDTokenAddressSet(_atidTokenAddress);
        emit BAITokenAddressSet(_baiTokenAddress);
        emit COLTokenAddressSet(_colTokenAddress);
        emit VaultManagerAddressSet(_vaultManagerAddress);
        emit BorrowerOperationsAddressSet(_borrowerOperationsAddress);
        emit ActivePoolAddressSet(_activePoolAddress);
        emit GovTokenAddressSet(_govTokenAddress);

        // _renounceOwnership();
    }

    function _insertLockedStake(address _stakerAddress, uint _ATIDamount, uint _stakeWeight, uint _lockedUntil) internal returns (uint newLockedStakeID) {
        // Get (or init) next ID and increment.
        if (nextLockedStakeIDMap[_stakerAddress] == 0) {
            nextLockedStakeIDMap[_stakerAddress] = 1;
        }
        uint nextLockedStateID = nextLockedStakeIDMap[_stakerAddress];
        nextLockedStakeIDMap[_stakerAddress]++;

        // Create and insert the new stakes into the map.
        LockedStake memory newLockedStake = LockedStake({
            active: true,

            ID: nextLockedStateID,
            prevID: tailLockedStakeIDMap[_stakerAddress],  // Can be 0.
            nextID: 0,  // New tail.

            amount: _ATIDamount,
            lockedUntil: _lockedUntil,
            stakeWeight: _stakeWeight
        });
        lockedStakeMap[_stakerAddress][newLockedStake.ID] = newLockedStake;

        // Insert new stakes into the linked list for easier lookup of existing stakes.
        if (headLockedStakeIDMap[_stakerAddress] == 0) {
            // First element in the linked list. Set it also as head.
            headLockedStakeIDMap[_stakerAddress] = newLockedStake.ID;
        } else {
            // Connect with its previous locked stakes, and set it as the new tail.
            lockedStakeMap[_stakerAddress][newLockedStake.prevID].nextID = newLockedStake.ID;
        }
        // The inserted locked stake is the new tail.
        tailLockedStakeIDMap[_stakerAddress] = newLockedStake.ID;

        // Add the weighted stakes to total accounting.
        uint newWeightedStake = newLockedStake.amount * newLockedStake.stakeWeight;
        weightedStakes[_stakerAddress] += newWeightedStake;
        totalWeightedATIDStaked += newWeightedStake;

        emit WeightedStakeAdded(msg.sender, newLockedStake.ID, _ATIDamount, newWeightedStake, weightedStakes[_stakerAddress], _lockedUntil);
        emit TotalWeightedATIDStakedUpdated(totalWeightedATIDStaked);
        // For querying purposes, record unweighted stakes.
        unweightedStakes[_stakerAddress] += _ATIDamount;
        totalUnweightedATIDStaked += _ATIDamount;

        return newLockedStake.ID;
    }

    function _removeLockedStake(address _stakerAddress, uint _lockedStakeID) internal returns (uint atidAmountWithdrawn, uint stakeWeight) {
        require(lockedStakeMap[_stakerAddress][_lockedStakeID].active, "ATIDStaking: invalid locked stakes");
        require(lockedStakeMap[_stakerAddress][_lockedStakeID].lockedUntil < block.timestamp, "ATIDStaking: unlock timestamp not reached");

        LockedStake memory lockedStake = lockedStakeMap[_stakerAddress][_lockedStakeID];
        atidAmountWithdrawn = lockedStake.amount;
        stakeWeight = lockedStake.stakeWeight;

        // Update linked list structures.
        if (headLockedStakeIDMap[_stakerAddress] == lockedStake.ID) {
            // Is linked list head.
            headLockedStakeIDMap[_stakerAddress] = lockedStake.nextID;  // Can be 0.
        } else {
            // Not linked list head.
            lockedStakeMap[_stakerAddress][lockedStake.prevID].nextID = lockedStake.nextID;  // Can be 0.
        }
        if (tailLockedStakeIDMap[_stakerAddress] == lockedStake.ID) {
            // Is linked list tail.
            tailLockedStakeIDMap[_stakerAddress] = lockedStake.prevID;  // Can be 0.
        } else {
            // Not linked list tail.
            lockedStakeMap[_stakerAddress][lockedStake.nextID].prevID = lockedStake.prevID;  // Can be 0.
        }

        // Remove the stakes from total accounting.
        uint removedWeightedStake = lockedStake.amount * lockedStake.stakeWeight;
        weightedStakes[_stakerAddress] -= removedWeightedStake;
        totalWeightedATIDStaked -= removedWeightedStake;

        emit WeightedStakeRemoved(msg.sender, _lockedStakeID, lockedStake.amount, removedWeightedStake, weightedStakes[_stakerAddress]);
        emit TotalWeightedATIDStakedUpdated(totalWeightedATIDStaked);
        // For querying purposes, record unweighted stakes.
        unweightedStakes[_stakerAddress] -= lockedStake.amount;
        totalUnweightedATIDStaked -= lockedStake.amount;

        delete lockedStakeMap[_stakerAddress][_lockedStakeID];

        return (atidAmountWithdrawn, stakeWeight);
    }

    // If caller has a pre-existing stake, send any accumulated collateral and BAI gains to them. 
    function stakeLocked(uint _ATIDamount, uint _lockedUntil) external override nonReentrant {
        _requireNonZeroAmount(_ATIDamount);

        uint currentWeightedStake = weightedStakes[msg.sender];

        uint COLGain;
        uint BAIGain;
        // Grab any accumulated COL and BAI gains from the current stake
        if (currentWeightedStake != 0) {
            COLGain = _getPendingCOLGain(msg.sender);
            BAIGain = _getPendingBAIGain(msg.sender);
        }
    
        // Updating snapshots ensures that fees calculated with previous weighted stake amount
        // it paid out, and the new weighted stake amount will be applied for future fees.
        _updateUserSnapshots(msg.sender);

        // Calculate weights for staking, based on how many years the unlock time is from now.
        uint stakeWeight = _getStakeWeight(_lockedUntil);

        // Insert the new locked stake
        _insertLockedStake(msg.sender, _ATIDamount, stakeWeight, _lockedUntil);

        // Transfer ATID from caller to this contract
        atidToken.sendToATIDStaking(msg.sender, _ATIDamount);

        emit StakingGainsWithdrawn(msg.sender, BAIGain, COLGain);

         // Send accumulated BAI and collateral gains to the caller
        if (currentWeightedStake != 0) {
            require(baiToken.transfer(msg.sender, BAIGain), "ATIDStaking: cannot receive BAI gains");
            _sendCOLGainToUser(COLGain);
        }

        // Mint corresponding amount of GovToken by weight.
        govToken.mint(msg.sender, _ATIDamount * stakeWeight);
    }

    // Unstake the ATID and send it back to the caller, along with their accumulated BAI & collateral gains. 
    // If provided with an invalid locked stake ID (e.g. 0), does the existing fee claiming.
    function unstakeLocked(uint _lockedStakeID) external override nonReentrant {
        uint currentStake = weightedStakes[msg.sender];
        _requireUserHasStake(currentStake);

        // Grab any accumulated COL and BAI gains from the current stake
        uint COLGain = _getPendingCOLGain(msg.sender);
        uint BAIGain = _getPendingBAIGain(msg.sender);
        
        // Updating snapshots ensures that fees calculated with previous weighted stake amount
        // it paid out, and the new weighted stake amount will be applied for future fees.
        _updateUserSnapshots(msg.sender);

        // If this condition is false, the user is basically just doing a fee reward withdrawal.
        if (lockedStakeMap[msg.sender][_lockedStakeID].active) {
            (uint ATIDToWithdraw, uint stakeWeight) = _removeLockedStake(msg.sender, _lockedStakeID);

            // Transfer unstaked ATID to user
            require(atidToken.transfer(msg.sender, ATIDToWithdraw), "ATIDStaking: cannot receive staked ATID");

            // Burn corresponding amount of GovToken by weight.
            govToken.burn(msg.sender, ATIDToWithdraw * stakeWeight);
        }

        emit StakingGainsWithdrawn(msg.sender, BAIGain, COLGain);

        // Send accumulated BAI and collateral gains to the caller
        require(baiToken.transfer(msg.sender, BAIGain), "ATIDStaking: cannot receive BAI gains");
        _sendCOLGainToUser(COLGain);
    }

    // --- Reward-per-unit-staked increase functions. Called by Astrid core contracts ---

    function increaseF_COL(uint _COLFee) external override {
        _requireCallerIsVaultManager();
        uint COLFeePerATIDStaked;
     
        if (totalWeightedATIDStaked > 0) {COLFeePerATIDStaked = _COLFee.mul(DECIMAL_PRECISION).div(totalWeightedATIDStaked);}

        F_COL = F_COL.add(COLFeePerATIDStaked); 
        emit F_COLUpdated(F_COL);
    }

    function increaseF_BAI(uint _BAIFee) external override {
        _requireCallerIsBorrowerOperations();
        uint BAIFeePerATIDStaked;
        
        if (totalWeightedATIDStaked > 0) {BAIFeePerATIDStaked = _BAIFee.mul(DECIMAL_PRECISION).div(totalWeightedATIDStaked);}
        
        F_BAI = F_BAI.add(BAIFeePerATIDStaked);
        emit F_BAIUpdated(F_BAI);
    }

    // --- Pending reward functions ---

    function getPendingCOLGain(address _user) external view override returns (uint) {
        return _getPendingCOLGain(_user);
    }

    function _getPendingCOLGain(address _user) internal view returns (uint) {
        uint F_COL_Snapshot = snapshots[_user].F_COL_Snapshot;
        uint COLGain = weightedStakes[_user].mul(F_COL.sub(F_COL_Snapshot)).div(DECIMAL_PRECISION);
        return COLGain;
    }

    function getPendingBAIGain(address _user) external view override returns (uint) {
        return _getPendingBAIGain(_user);
    }

    function _getPendingBAIGain(address _user) internal view returns (uint) {
        uint F_BAI_Snapshot = snapshots[_user].F_BAI_Snapshot;
        uint BAIGain = weightedStakes[_user].mul(F_BAI.sub(F_BAI_Snapshot)).div(DECIMAL_PRECISION);
        return BAIGain;
    }

    // --- Internal helper functions ---

    // Calculate weights for staking, based on how many years the unlock time is from now.
    function _getStakeWeight(uint _lockedUntil) internal view returns (uint stakeWeight) {
        uint yearsToStake = 0;
        if (_lockedUntil > block.timestamp) {
            yearsToStake = (_lockedUntil - block.timestamp) / SECONDS_IN_ONE_YEAR;
            // Max allowed locking years timeframe is 3, last index of WEIGHT_MULTIPLIERS.
            if (yearsToStake > 3) {
                yearsToStake = 3;
            }
        }
        stakeWeight = WEIGHT_MULTIPLIERS[yearsToStake];
    }

    function _updateUserSnapshots(address _user) internal {
        snapshots[_user].F_COL_Snapshot = F_COL;
        snapshots[_user].F_BAI_Snapshot = F_BAI;
        emit StakerSnapshotsUpdated(_user, F_COL, F_BAI);
    }

    function _sendCOLGainToUser(uint COLGain) internal {
        emit COLSent(msg.sender, COLGain);
        bool success = colToken.transfer(msg.sender, COLGain);
        require(success, "ATIDStaking: Failed to send accumulated COLGain");
    }

    // --- 'require' functions ---

    function _requireCallerIsVaultManager() internal view {
        require(msg.sender == vaultManagerAddress, "ATIDStaking: caller is not VaultM");
    }

    function _requireCallerIsBorrowerOperations() internal view {
        require(msg.sender == borrowerOperationsAddress, "ATIDStaking: caller is not BorrowerOps");
    }

    function _requireCallerIsActivePool() internal view {
        require(msg.sender == activePoolAddress, "ATIDStaking: caller is not ActivePool");
    }

    function _requireUserHasStake(uint currentStake) internal pure {  
        require(currentStake > 0, "ATIDStaking: User must have a non-zero stake");  
    }

    function _requireNonZeroAmount(uint _amount) internal pure {
        require(_amount > 0, "ATIDStaking: Amount must be non-zero");
    }

    // TODO: ATIDStaking is no longer payable. Do ERC20 transfers instead.
    // receive() external payable {
    //     _requireCallerIsActivePool();
    // }
}
