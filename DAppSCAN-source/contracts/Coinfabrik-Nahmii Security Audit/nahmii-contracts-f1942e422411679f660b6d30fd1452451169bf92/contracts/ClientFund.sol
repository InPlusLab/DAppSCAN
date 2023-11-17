/*
 * Hubii Nahmii
 *
 * Compliant with the Hubii Nahmii specification v0.12.
 *
 * Copyright (C) 2017-2018 Hubii AS
 */

pragma solidity ^0.4.25;
pragma experimental ABIEncoderV2;

import {Ownable} from "./Ownable.sol";
import {Beneficiary} from "./Beneficiary.sol";
import {Benefactor} from "./Benefactor.sol";
import {AuthorizableServable} from "./AuthorizableServable.sol";
import {TransferControllerManageable} from "./TransferControllerManageable.sol";
import {BalanceTrackable} from "./BalanceTrackable.sol";
import {TransactionTrackable} from "./TransactionTrackable.sol";
import {WalletLockable} from "./WalletLockable.sol";
import {TransferController} from "./TransferController.sol";
import {SafeMathIntLib} from "./SafeMathIntLib.sol";
import {TokenHolderRevenueFund} from "./TokenHolderRevenueFund.sol";

/**
 * @title Client fund
 * @notice Where clients’ crypto is deposited into, staged and withdrawn from.
 */
contract ClientFund is Ownable, Beneficiary, Benefactor, AuthorizableServable, TransferControllerManageable,
BalanceTrackable, TransactionTrackable, WalletLockable {
    using SafeMathIntLib for int256;

    address[] public seizedWallets;
    mapping(address => bool) public seizedByWallet;

    TokenHolderRevenueFund public tokenHolderRevenueFund;

    //
    // Events
    // -----------------------------------------------------------------------------------------------------------------
    event SetTokenHolderRevenueFundEvent(TokenHolderRevenueFund oldTokenHolderRevenueFund,
        TokenHolderRevenueFund newTokenHolderRevenueFund);
    event ReceiveEvent(address wallet, string balanceType, int256 value, address currencyCt,
        uint256 currencyId, string standard);
    event WithdrawEvent(address wallet, int256 value, address currencyCt, uint256 currencyId,
        string standard);
    event StageEvent(address wallet, int256 value, address currencyCt, uint256 currencyId);
    event UnstageEvent(address wallet, int256 value, address currencyCt, uint256 currencyId);
    event UpdateSettledBalanceEvent(address wallet, int256 value, address currencyCt,
        uint256 currencyId);
    event StageToBeneficiaryEvent(address sourceWallet, address beneficiary, int256 value,
        address currencyCt, uint256 currencyId, string standard);
    event TransferToBeneficiaryEvent(address wallet, address beneficiary, int256 value,
        address currencyCt, uint256 currencyId);
    event SeizeBalancesEvent(address seizedWallet, address seizerWallet, int256 value,
        address currencyCt, uint256 currencyId);
    event ClaimRevenueEvent(address claimer, string balanceType, address currencyCt,
        uint256 currencyId, string standard);

    //
    // Constructor
    // -----------------------------------------------------------------------------------------------------------------
    constructor(address deployer) Ownable(deployer) Beneficiary() Benefactor()
    public
    {
        serviceActivationTimeout = 1 weeks;
    }

    //
    // Functions
    // -----------------------------------------------------------------------------------------------------------------
    /// @notice Set the token holder revenue fund contract
    /// @param newTokenHolderRevenueFund The (address of) TokenHolderRevenueFund contract instance
    function setTokenHolderRevenueFund(TokenHolderRevenueFund newTokenHolderRevenueFund)
    public
    onlyDeployer
    notNullAddress(newTokenHolderRevenueFund)
    notSameAddresses(newTokenHolderRevenueFund, tokenHolderRevenueFund)
    {
        // Set new token holder revenue fund
        TokenHolderRevenueFund oldTokenHolderRevenueFund = tokenHolderRevenueFund;
        tokenHolderRevenueFund = newTokenHolderRevenueFund;

        // Emit event
        emit SetTokenHolderRevenueFundEvent(oldTokenHolderRevenueFund, newTokenHolderRevenueFund);
    }

    /// @notice Fallback function that deposits ethers to msg.sender's deposited balance
    function()
    public
    payable
    {
        receiveEthersTo(msg.sender, balanceTracker.DEPOSITED_BALANCE_TYPE());
    }

    /// @notice Receive ethers to the given wallet's balance of the given type
    /// @param wallet The address of the concerned wallet
    /// @param balanceType The target balance type
    function receiveEthersTo(address wallet, string balanceType)
    public
    payable
    {
        int256 value = SafeMathIntLib.toNonZeroInt256(msg.value);

        // Register reception
        _receiveTo(wallet, balanceType, value, address(0), 0, true);

        // Emit event
        emit ReceiveEvent(wallet, balanceType, value, address(0), 0, "");
    }

    /// @notice Receive token to msg.sender's balance of the given type
    /// @dev The wallet must approve of this ClientFund's transfer prior to calling this function
    /// @param balanceType The target balance type
    /// @param value The value (amount of fungible, id of non-fungible) to receive
    /// @param currencyCt The address of the concerned currency contract (address(0) == ETH)
    /// @param currencyId The ID of the concerned currency (0 for ETH and ERC20)
    /// @param standard The standard of the token ("" for default registered, "ERC20", "ERC721")
    function receiveTokens(string balanceType, int256 value, address currencyCt,
        uint256 currencyId, string standard)
    public
    {
        receiveTokensTo(msg.sender, balanceType, value, currencyCt, currencyId, standard);
    }

    /// @notice Receive token to the given wallet's balance of the given type
    /// @dev The wallet must approve of this ClientFund's transfer prior to calling this function
    /// @param wallet The address of the concerned wallet
    /// @param balanceType The target balance type
    /// @param value The value (amount of fungible, id of non-fungible) to receive
    /// @param currencyCt The address of the concerned currency contract (address(0) == ETH)
    /// @param currencyId The ID of the concerned currency (0 for ETH and ERC20)
    function receiveTokensTo(address wallet, string balanceType, int256 value, address currencyCt,
        uint256 currencyId, string standard)
    public
    {
        require(value.isNonZeroPositiveInt256());

        // Get transfer controller
        TransferController controller = transferController(currencyCt, standard);

        // Execute transfer
        require(
            address(controller).delegatecall(
                controller.getReceiveSignature(), msg.sender, this, uint256(value), currencyCt, currencyId
            )
        );

        // Register reception
        _receiveTo(wallet, balanceType, value, currencyCt, currencyId, controller.isFungible());

        // Emit event
        emit ReceiveEvent(wallet, balanceType, value, currencyCt, currencyId, standard);
    }

    /// @notice Update the settled balance by the difference between provided off-chain balance amount
    /// and deposited on-chain balance, where deposited balance is resolved at the given block number
    /// @param wallet The address of the concerned wallet
    /// @param value The target balance value (amount of fungible, id of non-fungible), i.e. off-chain balance
    /// @param currencyCt The address of the concerned currency contract (address(0) == ETH)
    /// @param currencyId The ID of the concerned currency (0 for ETH and ERC20)
    /// @param standard The standard of the token ("" for default registered, "ERC20", "ERC721")
    /// @param blockNumber The block number to which the settled balance is updated
    function updateSettledBalance(address wallet, int256 value, address currencyCt, uint256 currencyId,
        string standard, uint256 blockNumber)
    public
    onlyAuthorizedService(wallet)
    notNullAddress(wallet)
    {
        require(value.isPositiveInt256());

        if (_isFungible(currencyCt, currencyId, standard)) {
            (int256 depositedValue,) = balanceTracker.fungibleRecordByBlockNumber(
                wallet, balanceTracker.depositedBalanceType(), currencyCt, currencyId, blockNumber
            );
            balanceTracker.set(
                wallet, balanceTracker.settledBalanceType(), value.sub(depositedValue),
                currencyCt, currencyId, true
            );

        } else {
            balanceTracker.sub(
                wallet, balanceTracker.depositedBalanceType(), value, currencyCt, currencyId, false
            );
            balanceTracker.add(
                wallet, balanceTracker.settledBalanceType(), value, currencyCt, currencyId, false
            );
        }

        // Emit event
        emit UpdateSettledBalanceEvent(wallet, value, currencyCt, currencyId);
    }

    /// @notice Stage a value for subsequent withdrawal
    /// @param wallet The address of the concerned wallet
    /// @param value The value (amount of fungible, id of non-fungible) to deposit
    /// @param currencyCt The address of the concerned currency contract (address(0) == ETH)
    /// @param currencyId The ID of the concerned currency (0 for ETH and ERC20)
    /// @param standard The standard of the token ("" for default registered, "ERC20", "ERC721")
    function stage(address wallet, int256 value, address currencyCt, uint256 currencyId,
        string standard)
    public
    onlyAuthorizedService(wallet)
    {
        require(value.isNonZeroPositiveInt256());

        // Deduce fungibility
        bool fungible = _isFungible(currencyCt, currencyId, standard);

        // Subtract stage value from settled, possibly also from deposited
        value = _subtractSequentially(wallet, balanceTracker.activeBalanceTypes(), value, currencyCt, currencyId, fungible);

        // Add to staged
        balanceTracker.add(
            wallet, balanceTracker.stagedBalanceType(), value, currencyCt, currencyId, fungible
        );

        // Emit event
        emit StageEvent(wallet, value, currencyCt, currencyId);
    }

    /// @notice Unstage a staged value
    /// @param value The value (amount of fungible, id of non-fungible) to deposit
    /// @param currencyCt The address of the concerned currency contract (address(0) == ETH)
    /// @param currencyId The ID of the concerned currency (0 for ETH and ERC20)
    /// @param standard The standard of the token ("" for default registered, "ERC20", "ERC721")
    function unstage(int256 value, address currencyCt, uint256 currencyId, string standard)
    public
    {
        require(value.isNonZeroPositiveInt256());

        // Deduce fungibility
        bool fungible = _isFungible(currencyCt, currencyId, standard);

        // Subtract unstage value from staged
        value = _subtractFromStaged(msg.sender, value, currencyCt, currencyId, fungible);

        balanceTracker.add(
            msg.sender, balanceTracker.depositedBalanceType(), value, currencyCt, currencyId, fungible
        );

        // Emit event
        emit UnstageEvent(msg.sender, value, currencyCt, currencyId);
    }

    /// @notice Stage the value from wallet to the given beneficiary and targeted to wallet
    /// @param wallet The address of the concerned wallet
    /// @param beneficiary The (address of) concerned beneficiary contract
    /// @param value The value (amount of fungible, id of non-fungible) to stage
    /// @param currencyCt The address of the concerned currency contract (address(0) == ETH)
    /// @param currencyId The ID of the concerned currency (0 for ETH and ERC20)
    /// @param standard The standard of the token ("" for default registered, "ERC20", "ERC721")
    function stageToBeneficiary(address wallet, Beneficiary beneficiary, int256 value,
        address currencyCt, uint256 currencyId, string standard)
    public
    onlyAuthorizedService(wallet)
    {
        // Deduce fungibility
        bool fungible = _isFungible(currencyCt, currencyId, standard);

        // Subtract stage value from settled, possibly also from deposited
        value = _subtractSequentially(wallet, balanceTracker.activeBalanceTypes(), value, currencyCt, currencyId, fungible);

        // Execute transfer
        _transferToBeneficiary(wallet, beneficiary, value, currencyCt, currencyId, standard);

        // Emit event
        emit StageToBeneficiaryEvent(wallet, beneficiary, value, currencyCt, currencyId, standard);
    }

    /// @notice Transfer the given value of currency to the given beneficiary without target wallet
    /// @param wallet The address of the concerned wallet
    /// @param beneficiary The (address of) concerned beneficiary contract
    /// @param value The value (amount of fungible, id of non-fungible) to transfer
    /// @param currencyCt The address of the concerned currency contract (address(0) == ETH)
    /// @param currencyId The ID of the concerned currency (0 for ETH and ERC20)
    /// @param standard The standard of the token ("" for default registered, "ERC20", "ERC721")
    function transferToBeneficiary(address wallet, Beneficiary beneficiary, int256 value,
        address currencyCt, uint256 currencyId, string standard)
    public
    onlyAuthorizedService(wallet)
    {
        // Execute transfer
        _transferToBeneficiary(wallet, beneficiary, value, currencyCt, currencyId, standard);

        // Emit event
        emit TransferToBeneficiaryEvent(wallet, beneficiary, value, currencyCt, currencyId);
    }

    /// @notice Seize balances in the given currency of the given wallet, provided that the wallet
    /// is locked by the caller
    /// @param wallet The address of the concerned wallet whose balances are seized
    /// @param currencyCt The address of the concerned currency contract (address(0) == ETH)
    /// @param currencyId The ID of the concerned currency (0 for ETH and ERC20)
    /// @param standard The standard of the token ("" for default registered, "ERC20", "ERC721")
    function seizeBalances(address wallet, address currencyCt, uint256 currencyId, string standard)
    public
    {
        if (_isFungible(currencyCt, currencyId, standard))
            _seizeFungibleBalances(wallet, msg.sender, currencyCt, currencyId);

        else
            _seizeNonFungibleBalances(wallet, msg.sender, currencyCt, currencyId);

        // Add to the store of seized wallets
        if (!seizedByWallet[wallet]) {
            seizedByWallet[wallet] = true;
            seizedWallets.push(wallet);
        }
    }

    /// @notice Withdraw the given amount from staged balance
    /// @param value The value (amount of fungible, id of non-fungible) to withdraw
    /// @param currencyCt The address of the concerned currency contract (address(0) == ETH)
    /// @param currencyId The ID of the concerned currency (0 for ETH and ERC20)
    /// @param standard The standard of the token ("" for default registered, "ERC20", "ERC721")
    function withdraw(int256 value, address currencyCt, uint256 currencyId, string standard)
    public
    {
        require(value.isNonZeroPositiveInt256());

        // Require that msg.sender and currency is not locked
        require(!walletLocker.isLocked(msg.sender, currencyCt, currencyId));

        // Deduce fungibility
        bool fungible = _isFungible(currencyCt, currencyId, standard);

        // Subtract unstage value from staged
        value = _subtractFromStaged(msg.sender, value, currencyCt, currencyId, fungible);

        // Log record of this transaction
        transactionTracker.add(
            msg.sender, transactionTracker.withdrawalTransactionType(), value, currencyCt, currencyId
        );

        // Execute transfer
        _transferToWallet(msg.sender, value, currencyCt, currencyId, standard);

        // Emit event
        emit WithdrawEvent(msg.sender, value, currencyCt, currencyId, standard);
    }

    /// @notice Get the seized status of given wallet
    /// @param wallet The address of the concerned wallet
    /// @return true if wallet is seized, false otherwise
    function isSeizedWallet(address wallet)
    public
    view
    returns (bool)
    {
        return seizedByWallet[wallet];
    }

    /// @notice Get the number of wallets whose funds have been seized
    /// @return Number of wallets
    function seizedWalletsCount()
    public
    view
    returns (uint256)
    {
        return seizedWallets.length;
    }

    /// @notice Claim revenue from token holder revenue fund based this contract's holdings of the
    /// revenue token, this so that revenue may be shared amongst revenue token holders in nahmii
    /// @param claimer The concerned address of claimer that will subsequently distribute revenue in nahmii
    /// @param balanceType The target balance type for the reception in this contract
    /// @param currencyCt The address of the concerned currency contract (address(0) == ETH)
    /// @param currencyId The ID of the concerned currency (0 for ETH and ERC20)
    /// @param standard The standard of the token ("" for default registered, "ERC20", "ERC721")
    function claimRevenue(address claimer, string balanceType, address currencyCt,
        uint256 currencyId, string standard)
    public
    onlyOperator
    {
        tokenHolderRevenueFund.claimAndTransferToBeneficiary(
            this, claimer, balanceType,
            currencyCt, currencyId, standard
        );

        emit ClaimRevenueEvent(claimer, balanceType, currencyCt, currencyId, standard);
    }

    //
    // Private functions
    // -----------------------------------------------------------------------------------------------------------------
    function _receiveTo(address wallet, string balanceType, int256 value, address currencyCt,
        uint256 currencyId, bool fungible)
    private
    {
        bytes32 balanceHash = 0 < bytes(balanceType).length ?
        keccak256(abi.encodePacked(balanceType)) :
        balanceTracker.depositedBalanceType();

        // Add to per-wallet staged balance
        if (balanceTracker.stagedBalanceType() == balanceHash)
            balanceTracker.add(
                wallet, balanceTracker.stagedBalanceType(), value, currencyCt, currencyId, fungible
            );

        // Add to per-wallet deposited balance
        else if (balanceTracker.depositedBalanceType() == balanceHash) {
            balanceTracker.add(
                wallet, balanceTracker.depositedBalanceType(), value, currencyCt, currencyId, fungible
            );

            // Log record of this transaction
            transactionTracker.add(
                wallet, transactionTracker.depositTransactionType(), value, currencyCt, currencyId
            );
        }

        else
            revert();
    }

    function _subtractSequentially(address wallet, bytes32[] balanceTypes, int256 value, address currencyCt,
        uint256 currencyId, bool fungible)
    private
    returns (int256)
    {
        if (fungible)
            return _subtractFungibleSequentially(wallet, balanceTypes, value, currencyCt, currencyId);
        else
            return _subtractNonFungibleSequentially(wallet, balanceTypes, value, currencyCt, currencyId);
    }

    function _subtractFungibleSequentially(address wallet, bytes32[] balanceTypes, int256 amount, address currencyCt, uint256 currencyId)
    private
    returns (int256)
    {
        // Require positive amount
        require(0 <= amount);

        uint256 i;
        int256 totalBalanceAmount = 0;
        for (i = 0; i < balanceTypes.length; i++)
            totalBalanceAmount = totalBalanceAmount.add(
                balanceTracker.get(
                    wallet, balanceTypes[i], currencyCt, currencyId
                )
            );

        // Clamp amount to stage
        amount = amount.clampMax(totalBalanceAmount);

        int256 _amount = amount;
        for (i = 0; i < balanceTypes.length; i++) {
            int256 typeAmount = balanceTracker.get(
                wallet, balanceTypes[i], currencyCt, currencyId
            );

            if (typeAmount >= _amount) {
                balanceTracker.sub(
                    wallet, balanceTypes[i], _amount, currencyCt, currencyId, true
                );
                break;

            } else {
                balanceTracker.set(
                    wallet, balanceTypes[i], 0, currencyCt, currencyId, true
                );
                _amount = _amount.sub(typeAmount);
            }
        }

        return amount;
    }

    function _subtractNonFungibleSequentially(address wallet, bytes32[] balanceTypes, int256 id, address currencyCt, uint256 currencyId)
    private
    returns (int256)
    {
        for (uint256 i = 0; i < balanceTypes.length; i++)
            if (balanceTracker.hasId(wallet, balanceTypes[i], id, currencyCt, currencyId)) {
                balanceTracker.sub(wallet, balanceTypes[i], id, currencyCt, currencyId, false);
                break;
            }

        return id;
    }

    function _subtractFromStaged(address wallet, int256 value, address currencyCt, uint256 currencyId, bool fungible)
    private
    returns (int256)
    {
        if (fungible) {
            // Clamp value to unstage
            value = value.clampMax(
                balanceTracker.get(wallet, balanceTracker.stagedBalanceType(), currencyCt, currencyId)
            );

            // Require positive value
            require(0 <= value);

        } else {
            // Require that value is included in staged balance
            require(balanceTracker.hasId(wallet, balanceTracker.stagedBalanceType(), value, currencyCt, currencyId));
        }

        // Subtract from deposited balance
        balanceTracker.sub(wallet, balanceTracker.stagedBalanceType(), value, currencyCt, currencyId, fungible);

        return value;
    }

    function _transferToBeneficiary(address destWallet, Beneficiary beneficiary,
        int256 value, address currencyCt, uint256 currencyId, string standard)
    private
    {
        require(value.isNonZeroPositiveInt256());
        require(isRegisteredBeneficiary(beneficiary));

        // Transfer funds to the beneficiary
        if (address(0) == currencyCt && 0 == currencyId)
            beneficiary.receiveEthersTo.value(uint256(value))(destWallet, "");

        else {
            // Approve of beneficiary
            TransferController controller = transferController(currencyCt, standard);
            require(
                address(controller).delegatecall(
                    controller.getApproveSignature(), beneficiary, uint256(value), currencyCt, currencyId
                )
            );

            // Transfer funds to the beneficiary
            beneficiary.receiveTokensTo(destWallet, "", value, currencyCt, currencyId, standard);
        }
    }

    function _transferToWallet(address wallet,
        int256 value, address currencyCt, uint256 currencyId, string standard)
    private
    {
        // Transfer ETH
        if (address(0) == currencyCt && 0 == currencyId)
            wallet.transfer(uint256(value));

        // Transfer token
        else {
            TransferController controller = transferController(currencyCt, standard);
            require(
                address(controller).delegatecall(
                    controller.getDispatchSignature(), this, wallet, uint256(value), currencyCt, currencyId
                )
            );
        }
    }

    function _seizeFungibleBalances(address lockedWallet, address lockerWallet, address currencyCt,
        uint256 currencyId)
    private
    {
        // Get the locked amount
        int256 amount = walletLocker.lockedAmount(lockedWallet, lockerWallet, currencyCt, currencyId);

        // Require that locked amount is strictly positive
        require(amount > 0);

        // Subtract stage value from settled, possibly also from deposited
        _subtractFungibleSequentially(lockedWallet, balanceTracker.allBalanceTypes(), amount, currencyCt, currencyId);

        // Add to staged balance of sender
        balanceTracker.add(
            lockerWallet, balanceTracker.stagedBalanceType(), amount, currencyCt, currencyId, true
        );

        // Emit event
        emit SeizeBalancesEvent(lockedWallet, lockerWallet, amount, currencyCt, currencyId);
    }

    function _seizeNonFungibleBalances(address lockedWallet, address lockerWallet, address currencyCt,
        uint256 currencyId)
    private
    {
        // Require that locked ids has entries
        uint256 lockedIdsCount = walletLocker.lockedIdsCount(lockedWallet, lockerWallet, currencyCt, currencyId);
        require(0 < lockedIdsCount);

        // Get the locked amount
        int256[] memory ids = walletLocker.lockedIdsByIndices(
            lockedWallet, lockerWallet, currencyCt, currencyId, 0, lockedIdsCount - 1
        );

        for (uint256 i = 0; i < ids.length; i++) {
            // Subtract from settled, possibly also from deposited
            _subtractNonFungibleSequentially(lockedWallet, balanceTracker.allBalanceTypes(), ids[i], currencyCt, currencyId);

            // Add to staged balance of sender
            balanceTracker.add(
                lockerWallet, balanceTracker.stagedBalanceType(), ids[i], currencyCt, currencyId, false
            );

            // Emit event
            emit SeizeBalancesEvent(lockedWallet, lockerWallet, ids[i], currencyCt, currencyId);
        }
    }

    function _isFungible(address currencyCt, uint256 currencyId, string standard)
    private
    view
    returns (bool)
    {
        return (address(0) == currencyCt && 0 == currencyId) || transferController(currencyCt, standard).isFungible();
    }
}
