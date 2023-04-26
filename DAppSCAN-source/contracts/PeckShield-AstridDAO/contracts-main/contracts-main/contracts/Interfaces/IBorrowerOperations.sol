// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

// Common interface for the Borrower Operations.
interface IBorrowerOperations {

    // --- Events ---

    event VaultManagerAddressChanged(address _newVaultManagerAddress);
    event ActivePoolAddressChanged(address _activePoolAddress);
    event DefaultPoolAddressChanged(address _defaultPoolAddress);
    event StabilityPoolAddressChanged(address _stabilityPoolAddress);
    event GasPoolAddressChanged(address _gasPoolAddress);
    event CollSurplusPoolAddressChanged(address _collSurplusPoolAddress);
    event PriceFeedAddressChanged(address  _newPriceFeedAddress);
    event SortedVaultsAddressChanged(address _sortedVaultsAddress);
    event COLTokenAddressChanged(address _colTokenAddress);
    event BAITokenAddressChanged(address _baiTokenAddress);
    event ATIDStakingAddressChanged(address _atidStakingAddress);

    event VaultCreated(address indexed _borrower, uint arrayIndex);
    event VaultUpdated(address indexed _borrower, uint _debt, uint _coll, uint stake, uint8 operation);
    event BAIBorrowingFeePaid(address indexed _borrower, uint _BAIFee);

    // --- Functions ---

    function setAddresses(
        address _vaultManagerAddress,
        address _activePoolAddress,
        address _defaultPoolAddress,
        address _stabilityPoolAddress,
        address _gasPoolAddress,
        address _collSurplusPoolAddress,
        address _priceFeedAddress,
        address _sortedVaultsAddress,
        address _colTokenAddress,
        address _baiTokenAddress,
        address _atidStakingAddress
    ) external;

    function openVault(uint _maxFee, uint _collateralAmount, uint _BAIAmount, address _upperHint, address _lowerHint) external;

    function addColl(uint _amount, address _upperHint, address _lowerHint) external;

    function moveCOLGainToVault(uint _amount, address _user, address _upperHint, address _lowerHint) external;

    function withdrawColl(uint _amount, address _upperHint, address _lowerHint) external;

    function withdrawBAI(uint _maxFee, uint _amount, address _upperHint, address _lowerHint) external;

    function repayBAI(uint _amount, address _upperHint, address _lowerHint) external;

    function closeVault() external;

    function adjustVault(uint _maxFee, uint _collChange, bool _isCollIncrease, uint _debtChange, bool isDebtIncrease, address _upperHint, address _lowerHint) external;

    function claimCollateral() external;

    function getCompositeDebt(uint _debt) external pure returns (uint);
}
