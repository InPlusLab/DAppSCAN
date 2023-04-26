// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.12;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "../interfaces/IAgToken.sol";
import "../interfaces/ISwapper.sol";
import "../interfaces/IVaultManager.sol";

/// @title Settlement
/// @author Angle Core Team
/// @notice Settlement Contract for a VaultManager
/// @dev This settlement contract should be activated by a careful governance which needs to have performed
/// some key operations before activating this contract
/// @dev In case of global settlement, there should be one settlement contract per `VaultManager`
contract Settlement {
    using SafeERC20 for IERC20;

    /// @notice Base used for parameter computation
    uint256 public constant BASE_PARAMS = 10**9;
    /// @notice Base used for interest computation
    uint256 public constant BASE_INTEREST = 10**27;
    /// @notice Base used for exchange rate computation. It is assumed
    /// that stablecoins have this base
    uint256 public constant BASE_STABLECOIN = 10**18;
    /// @notice Duration of the claim period for over-collateralized vaults
    uint256 public constant OVER_COLLATERALIZED_CLAIM_DURATION = 3 * 24 * 3600;

    // =============== Immutable references set in the constructor =================

    /// @notice `VaultManager` of this settlement contract
    IVaultManager public immutable vaultManager;
    /// @notice Reference to the stablecoin supported by the `VaultManager` contract
    IAgToken public immutable stablecoin;
    /// @notice Reference to the collateral supported by the `VaultManager`
    IERC20 public immutable collateral;
    /// @notice Base of the collateral
    uint256 internal immutable _collatBase;

    // ================ Variables frozen at settlement activation ==================

    /// @notice Value of the oracle for the collateral/stablecoin pair
    uint256 public oracleValue;
    /// @notice Value of the interest accumulator at settlement activation
    uint256 public interestAccumulator;
    /// @notice Timestamp at which settlement was activated
    uint256 public activationTimestamp;
    /// @notice Collateral factor of the `VaultManager`
    uint64 public collateralFactor;

    // =================== Variables updated during the process ====================

    /// @notice How much collateral you can get from stablecoins
    uint256 public collateralStablecoinExchangeRate;
    /// @notice Amount of collateral that will be left over at the end of the process
    uint256 public leftOverCollateral;
    /// @notice Whether the `collateralStablecoinExchangeRate` has been computed
    bool public exchangeRateComputed;
    /// @notice Maps a vault to 1 if it was claimed by its owner
    mapping(uint256 => uint256) public vaultCheck;

    // ================================ Events =====================================

    event GlobalClaimPeriodActivated(uint256 _collateralStablecoinExchangeRate);
    event Recovered(address indexed tokenAddress, address indexed to, uint256 amount);
    event SettlementActivated(uint256 startTimestamp);
    event VaultClaimed(uint256 vaultID, uint256 stablecoinAmount, uint256 collateralAmount);

    // ================================ Errors =====================================

    error GlobalClaimPeriodNotStarted();
    error InsolventVault();
    error NotGovernor();
    error NotOwner();
    error RestrictedClaimPeriodNotEnded();
    error SettlementNotInitialized();
    error VaultAlreadyClaimed();

    /// @notice Constructor of the contract
    /// @param _vaultManager Address of the `VaultManager` associated to this `Settlement` contract
    /// @dev Out of safety, this constructor reads values from the `VaultManager` contract directly
    constructor(IVaultManager _vaultManager) {
        vaultManager = _vaultManager;
        stablecoin = _vaultManager.stablecoin();
        collateral = _vaultManager.collateral();
        _collatBase = 10**(IERC20Metadata(address(collateral)).decimals());
    }

    /// @notice Checks whether the `msg.sender` has the governor role or not
    modifier onlyGovernor() {
        if (!(vaultManager.treasury().isGovernor(msg.sender))) revert NotGovernor();
        _;
    }

    /// @notice Activates the settlement contract
    /// @dev When calling this function governance should make sure to have:
    /// 1. Accrued the interest rate on the contract
    /// 2. Paused the contract
    /// 3. Recovered all the collateral available in the `VaultManager` contract either
    /// by doing a contract upgrade or by calling a `recoverERC20` method if supported
    function activateSettlement() external onlyGovernor {
        oracleValue = (vaultManager.oracle()).read();
        interestAccumulator = vaultManager.interestAccumulator();
        activationTimestamp = block.timestamp;
        collateralFactor = vaultManager.collateralFactor();
        emit SettlementActivated(block.timestamp);
    }

    /// @notice Allows the owner of an over-collateralized vault to claim its collateral upon bringing back all owed stablecoins
    /// @param vaultID ID of the vault to claim
    /// @param to Address to which collateral should be sent
    /// @param who Address which should be notified if needed of the transfer of stablecoins and collateral
    /// @param data Data to pass to the `who` contract for it to successfully give the correct amount of stablecoins
    /// to the `msg.sender` address
    /// @return Amount of collateral sent to the `to` address
    /// @return Amount of stablecoins sent to the contract
    /// @dev Claiming can only happen short after settlement activation
    /// @dev A vault cannot be claimed twice and only the owner of the vault can claim it (regardless of the approval logic)
    /// @dev Only over-collateralized vaults can be claimed from this medium
    function claimOverCollateralizedVault(
        uint256 vaultID,
        address to,
        address who,
        bytes memory data
    ) external returns (uint256, uint256) {
        if (activationTimestamp == 0 || block.timestamp > activationTimestamp + OVER_COLLATERALIZED_CLAIM_DURATION)
            revert SettlementNotInitialized();
        if (vaultCheck[vaultID] == 1) revert VaultAlreadyClaimed();
        if (vaultManager.ownerOf(vaultID) != msg.sender) revert NotOwner();
        (uint256 collateralAmount, uint256 normalizedDebt) = vaultManager.vaultData(vaultID);
        uint256 vaultDebt = (normalizedDebt * interestAccumulator) / BASE_INTEREST;
        if (collateralAmount * oracleValue * collateralFactor < vaultDebt * BASE_PARAMS * _collatBase)
            revert InsolventVault();
        vaultCheck[vaultID] = 1;
        emit VaultClaimed(vaultID, vaultDebt, collateralAmount);
        return _handleRepay(collateralAmount, vaultDebt, to, who, data);
    }

    /// @notice Activates the global claim period by setting the `collateralStablecoinExchangeRate` which is going to
    /// dictate how much of collateral will be recoverable for each stablecoin
    /// @dev This function can only be called by the governor in order to allow it in case multiple settlements happen across
    /// different `VaultManager` to rebalance the amount of stablecoins on each to make sure that across all settlement contracts
    /// a similar value of collateral can be obtained against a similar value of stablecoins
    function activateGlobalClaimPeriod() external onlyGovernor {
        if (activationTimestamp == 0 || block.timestamp <= activationTimestamp + OVER_COLLATERALIZED_CLAIM_DURATION)
            revert RestrictedClaimPeriodNotEnded();
        uint256 collateralBalance = collateral.balanceOf(address(this));
        uint256 leftOverDebt = (vaultManager.totalNormalizedDebt() * interestAccumulator) / BASE_INTEREST;
        uint256 stablecoinBalance = stablecoin.balanceOf(address(this));
        // How much 1 of stablecoin will give you in collateral
        uint256 _collateralStablecoinExchangeRate;

        if (stablecoinBalance < leftOverDebt) {
            // The left over debt is the total debt minus the stablecoins which have already been accumulated
            // in the first phase
            leftOverDebt -= stablecoinBalance;
            // If you control all the debt, then you are entitled to get all the collateral left in the protocol
            _collateralStablecoinExchangeRate = (collateralBalance * BASE_STABLECOIN) / leftOverDebt;
            // But at the same time, you cannot get more collateral than the value of the stablecoins you brought
            uint256 maxExchangeRate = (BASE_STABLECOIN * _collatBase) / oracleValue;
            if (_collateralStablecoinExchangeRate >= maxExchangeRate) {
                // In this situation, we're sure that `leftOverCollateral` will be positive: governance should be wary
                // to call `recoverERC20` short after though as there's nothing that is going to prevent people to redeem
                // more stablecoins than the `leftOverDebt`
                leftOverCollateral = collateralBalance - (leftOverDebt * _collatBase) / oracleValue;
                _collateralStablecoinExchangeRate = maxExchangeRate;
            }
        }
        exchangeRateComputed = true;
        // In the else case where there is no debt left, you cannot get anything from your stablecoins
        // and so the `collateralStablecoinExchangeRate` is null
        collateralStablecoinExchangeRate = _collateralStablecoinExchangeRate;
        emit GlobalClaimPeriodActivated(_collateralStablecoinExchangeRate);
    }

    /// @notice Allows to claim collateral from stablecoins
    /// @param to Address to which collateral should be sent
    /// @param who Address which should be notified if needed of the transfer of stablecoins and collateral
    /// @param data Data to pass to the `who` contract for it to successfully give the correct amount of stablecoins
    /// to the `msg.sender` address
    /// @return Amount of collateral sent to the `to` address
    /// @return Amount of stablecoins sent to the contract
    /// @dev This function reverts if the `collateralStablecoinExchangeRate` is null and hence if the global claim period has
    /// not been activated
    function claimCollateralFromStablecoins(
        uint256 stablecoinAmount,
        address to,
        address who,
        bytes memory data
    ) external returns (uint256, uint256) {
        if (!exchangeRateComputed) revert GlobalClaimPeriodNotStarted();
        return
            _handleRepay(
                (stablecoinAmount * collateralStablecoinExchangeRate) / BASE_STABLECOIN,
                stablecoinAmount,
                to,
                who,
                data
            );
    }

    /// @notice Handles the simultaneous repayment of stablecoins with a transfer of collateral
    /// @param collateralAmountToGive Amount of collateral the contract should give
    /// @param stableAmountToRepay Amount of stablecoins the contract should burn from the call
    /// @param to Address to which stablecoins should be sent
    /// @param who Address which should be notified if needed of the transfer
    /// @param data Data to pass to the `who` contract for it to successfully give the correct amount of stablecoins
    /// to the `msg.sender` address
    /// @dev This function allows for capital-efficient claims of collateral from stablecoins
    function _handleRepay(
        uint256 collateralAmountToGive,
        uint256 stableAmountToRepay,
        address to,
        address who,
        bytes memory data
    ) internal returns (uint256, uint256) {
        collateral.safeTransfer(to, collateralAmountToGive);
        if (data.length > 0) {
            ISwapper(who).swap(
                collateral,
                IERC20(address(stablecoin)),
                msg.sender,
                stableAmountToRepay,
                collateralAmountToGive,
                data
            );
        }
        stablecoin.transferFrom(msg.sender, address(this), stableAmountToRepay);
        return (collateralAmountToGive, stableAmountToRepay);
    }

    /// @notice Recovers leftover tokens from the contract or tokens that were mistakenly sent to the contract
    /// @param tokenAddress Address of the token to recover
    /// @param to Address to send the remaining tokens to
    /// @param amountToRecover Amount to recover from the contract
    /// @dev Governors cannot recover more collateral than what would be leftover from the contract
    /// @dev This function can be used to rebalance stablecoin balances across different settlement contracts
    /// to make sure every stablecoin can be redeemed for the same value of collateral
    /// @dev It can also be used to recover tokens that are mistakenly sent to this contract
    function recoverERC20(
        address tokenAddress,
        address to,
        uint256 amountToRecover
    ) external onlyGovernor {
        if (tokenAddress == address(collateral)) {
            if (!exchangeRateComputed) revert GlobalClaimPeriodNotStarted();
            leftOverCollateral -= amountToRecover;
            collateral.safeTransfer(to, amountToRecover);
        } else {
            IERC20(tokenAddress).safeTransfer(to, amountToRecover);
        }
        emit Recovered(tokenAddress, to, amountToRecover);
    }
}
