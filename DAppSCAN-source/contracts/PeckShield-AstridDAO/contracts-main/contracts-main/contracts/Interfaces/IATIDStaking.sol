// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

interface IATIDStaking {

    // --- Events --
    
    event ATIDTokenAddressSet(address _atidTokenAddress);
    event BAITokenAddressSet(address _baiTokenAddress);
    event COLTokenAddressSet(address _colTokenAddress);
    event VaultManagerAddressSet(address _vaultManager);
    event BorrowerOperationsAddressSet(address _borrowerOperationsAddress);
    event ActivePoolAddressSet(address _activePoolAddress);
    event GovTokenAddressSet(address _govTokenAddress);

    event WeightedStakeAdded(address indexed staker, uint lockedStakeID, uint addedStake, uint addedWeightedStake, uint totalWeightedStake, uint lockedUntil);
    event WeightedStakeRemoved(address indexed staker, uint lockedStakeID, uint removedStake, uint removedWeightedStake, uint totalWeightedStake);
    event StakingGainsWithdrawn(address indexed staker, uint BAIGain, uint COLGain);
    event F_COLUpdated(uint _F_COL);
    event F_BAIUpdated(uint _F_BAI);
    event TotalWeightedATIDStakedUpdated(uint _totalWeightedATIDStaked);
    event COLSent(address _account, uint _amount);
    event StakerSnapshotsUpdated(address _staker, uint _F_COL, uint _F_BAI);

    // --- Functions ---

    function setAddresses
    (
        address _atidTokenAddress,
        address _baiTokenAddress,
        address _colTokenAddress,
        address _vaultManagerAddress, 
        address _borrowerOperationsAddress,
        address _activePoolAddress,
        address _govTokenAddress
    )  external;

    function stakeLocked(uint _ATIDamount, uint _unlockTimestamp) external;
    // function stake(uint _ATIDamount) external;

    function unstakeLocked(uint _lockedStakeID) external;
    // function unstake(uint _ATIDamount) external;

    function increaseF_COL(uint _COLFee) external; 

    function increaseF_BAI(uint _BAIFee) external;  

    function getPendingCOLGain(address _user) external view returns (uint);

    function getPendingBAIGain(address _user) external view returns (uint);
}
