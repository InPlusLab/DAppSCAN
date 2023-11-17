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
import {Configurable} from "./Configurable.sol";
import {AccrualBeneficiary} from "./AccrualBeneficiary.sol";
import {Servable} from "./Servable.sol";
import {TransferControllerManageable} from "./TransferControllerManageable.sol";
import {SafeMathIntLib} from "./SafeMathIntLib.sol";
import {SafeMathUintLib} from "./SafeMathUintLib.sol";
import {FungibleBalanceLib} from "./FungibleBalanceLib.sol";
import {TxHistoryLib} from "./TxHistoryLib.sol";
import {CurrenciesLib} from "./CurrenciesLib.sol";
import {MonetaryTypesLib} from "./MonetaryTypesLib.sol";
import {Beneficiary} from "./Beneficiary.sol";
import {TransferController} from "./TransferController.sol";
import {ConstantsLib} from "./ConstantsLib.sol";

/**
 * @title SecurityBond
 * @notice Fund that contains crypto incentive for challenging operator fraud.
 */
contract SecurityBond is Ownable, Configurable, AccrualBeneficiary, Servable, TransferControllerManageable {
    using SafeMathIntLib for int256;
    using SafeMathUintLib for uint256;
    using FungibleBalanceLib for FungibleBalanceLib.Balance;
    using TxHistoryLib for TxHistoryLib.TxHistory;
    using CurrenciesLib for CurrenciesLib.Currencies;

    //
    // Constants
    // -----------------------------------------------------------------------------------------------------------------
    string constant public REWARD_ACTION = "reward";
    string constant public DEPRIVE_ACTION = "deprive";

    //
    // Types
    // -----------------------------------------------------------------------------------------------------------------
    struct RewardMeta {
        uint256 rewardFraction;
        uint256 rewardNonce;
        uint256 unlockTime;
        mapping(address => mapping(uint256 => uint256)) claimNonceByCurrency;
    }

    //
    // Variables
    // -----------------------------------------------------------------------------------------------------------------
    FungibleBalanceLib.Balance private deposited;
    TxHistoryLib.TxHistory private txHistory;
    CurrenciesLib.Currencies private inUseCurrencies;

    mapping(address => RewardMeta) public rewardMetaByWallet;
    mapping(address => FungibleBalanceLib.Balance) private stagedByWallet;

    //
    // Events
    // -----------------------------------------------------------------------------------------------------------------
    event ReceiveEvent(address from, int256 amount, address currencyCt, uint256 currencyId);
    event RewardEvent(address wallet, uint256 rewardFraction, uint256 unlockTimeoutInSeconds);
    event DepriveEvent(address wallet);
    event ClaimAndTransferToBeneficiaryEvent(address from, Beneficiary beneficiary, string balanceType, int256 amount,
        address currencyCt, uint256 currencyId, string standard);
    event ClaimAndStageEvent(address from, int256 amount, address currencyCt, uint256 currencyId);
    event WithdrawEvent(address from, int256 amount, address currencyCt, uint256 currencyId, string standard);

    //
    // Constructor
    // -----------------------------------------------------------------------------------------------------------------
    constructor(address deployer) Ownable(deployer) Servable() public {
    }

    //
    // Functions
    // -----------------------------------------------------------------------------------------------------------------
    /// @notice Fallback function that deposits ethers
    function() public payable {
        receiveEthersTo(msg.sender, "");
    }

    /// @notice Receive ethers to
    /// @param wallet The concerned wallet address
    function receiveEthersTo(address wallet, string)
    public
    payable
    {
        int256 amount = SafeMathIntLib.toNonZeroInt256(msg.value);

        // Add to balance
        deposited.add(amount, address(0), 0);
        txHistory.addDeposit(amount, address(0), 0);

        // Add currency to in-use list
        inUseCurrencies.add(address(0), 0);

        // Emit event
        emit ReceiveEvent(wallet, amount, address(0), 0);
    }

    /// @notice Receive tokens
    /// @param amount The concerned amount
    /// @param currencyCt The address of the concerned currency contract (address(0) == ETH)
    /// @param currencyId The ID of the concerned currency (0 for ETH and ERC20)
    /// @param standard The standard of token ("ERC20", "ERC721")
    function receiveTokens(string, int256 amount, address currencyCt,
        uint256 currencyId, string standard)
    public
    {
        receiveTokensTo(msg.sender, "", amount, currencyCt, currencyId, standard);
    }

    /// @notice Receive tokens to
    /// @param wallet The address of the concerned wallet
    /// @param amount The concerned amount
    /// @param currencyCt The address of the concerned currency contract (address(0) == ETH)
    /// @param currencyId The ID of the concerned currency (0 for ETH and ERC20)
    /// @param standard The standard of token ("ERC20", "ERC721")
    function receiveTokensTo(address wallet, string, int256 amount, address currencyCt,
        uint256 currencyId, string standard)
    public
    {
        require(amount.isNonZeroPositiveInt256());

        // Execute transfer
        TransferController controller = transferController(currencyCt, standard);
        require(
            address(controller).delegatecall(
                controller.getReceiveSignature(), msg.sender, this, uint256(amount), currencyCt, currencyId
            )
        );

        // Add to balance
        deposited.add(amount, currencyCt, currencyId);
        txHistory.addDeposit(amount, currencyCt, currencyId);

        // Add currency to in-use list
        inUseCurrencies.add(currencyCt, currencyId);

        // Emit event
        emit ReceiveEvent(wallet, amount, currencyCt, currencyId);
    }

    /// @notice Get the count of deposits
    /// @return The count of deposits
    function depositsCount()
    public
    view
    returns (uint256)
    {
        return txHistory.depositsCount();
    }

    /// @notice Get the deposit at the given index
    /// @return The deposit at the given index
    function deposit(uint index)
    public
    view
    returns (int256 amount, uint256 blockNumber, address currencyCt, uint256 currencyId)
    {
        return txHistory.deposit(index);
    }

    /// @notice Get the deposited balance of the given currency
    /// @param currencyCt The address of the concerned currency contract (address(0) == ETH)
    /// @param currencyId The ID of the concerned currency (0 for ETH and ERC20)
    /// @return The deposited balance
    function depositedBalance(address currencyCt, uint256 currencyId)
    public
    view
    returns (int256)
    {
        return deposited.get(currencyCt, currencyId);
    }

    /// @notice Get the staged balance of the given currency
    /// @param currencyCt The address of the concerned currency contract (address(0) == ETH)
    /// @param currencyId The ID of the concerned currency (0 for ETH and ERC20)
    /// @return The deposited balance
    function stagedBalance(address wallet, address currencyCt, uint256 currencyId)
    public
    view
    returns (int256)
    {
        return stagedByWallet[wallet].get(currencyCt, currencyId);
    }

    /// @notice Get the count of currencies recorded
    /// @return The number of currencies
    function inUseCurrenciesCount()
    public
    view
    returns (uint256)
    {
        return inUseCurrencies.count();
    }

    /// @notice Get the currencies recorded with indices in the given range
    /// @param low The lower currency index
    /// @param up The upper currency index
    /// @return The currencies of the given index range
    function inUseCurrenciesByIndices(uint256 low, uint256 up)
    public
    view
    returns (MonetaryTypesLib.Currency[])
    {
        return inUseCurrencies.getByIndices(low, up);
    }

    /// @notice Get the claim nonce of the given wallet and currency
    /// @param wallet The concerned wallet
    /// @param currencyCt The address of the concerned currency contract (address(0) == ETH)
    /// @param currencyId The ID of the concerned currency (0 for ETH and ERC20)
    /// @return The claim nonce
    function claimNonceByWalletCurrency(address wallet, address currencyCt, uint256 currencyId)
    public
    view
    returns (uint256)
    {
        return rewardMetaByWallet[wallet].claimNonceByCurrency[currencyCt][currencyId];
    }

    /// @notice Reward the given wallet the given fraction of funds, where the reward is locked
    /// for the given number of seconds
    /// @param wallet The concerned wallet
    /// @param rewardFraction The fraction of sums that the wallet is rewarded
    /// @param unlockTimeoutInSeconds The number of seconds for which the reward is locked and should
    /// be claimed
    function reward(address wallet, uint256 rewardFraction, uint256 unlockTimeoutInSeconds)
    public
    notNullAddress(wallet)
    onlyEnabledServiceAction(REWARD_ACTION)
    {
        // Update reward
        rewardMetaByWallet[wallet].rewardFraction = rewardFraction.clampMax(uint256(ConstantsLib.PARTS_PER()));
        rewardMetaByWallet[wallet].rewardNonce++;
        rewardMetaByWallet[wallet].unlockTime = block.timestamp.add(unlockTimeoutInSeconds);

        // Emit event
        emit RewardEvent(wallet, rewardFraction, unlockTimeoutInSeconds);
    }

    /// @notice Deprive the given wallet of any reward it has been granted
    /// @param wallet The concerned wallet
    function deprive(address wallet)
    public
    onlyEnabledServiceAction(DEPRIVE_ACTION)
    {
        // Update reward
        rewardMetaByWallet[wallet].rewardFraction = 0;
        rewardMetaByWallet[wallet].rewardNonce++;
        rewardMetaByWallet[wallet].unlockTime = 0;

        // Emit event
        emit DepriveEvent(wallet);
    }

    /// @notice Claim reward and transfer to beneficiary
    /// @param beneficiary The concerned beneficiary
    /// @param balanceType The target balance type
    /// @param currencyCt The address of the concerned currency contract (address(0) == ETH)
    /// @param currencyId The ID of the concerned currency (0 for ETH and ERC20)
    /// @param standard The standard of the token ("" for default registered, "ERC20", "ERC721")
    function claimAndTransferToBeneficiary(Beneficiary beneficiary, string balanceType, address currencyCt,
        uint256 currencyId, string standard)
    public
    {
        // Claim reward
        int256 claimedAmount = _claim(msg.sender, currencyCt, currencyId);

        // Execute transfer
        if (address(0) == currencyCt && 0 == currencyId)
            beneficiary.receiveEthersTo.value(uint256(claimedAmount))(msg.sender, balanceType);

        else {
            TransferController controller = transferController(currencyCt, standard);
            require(
                address(controller).delegatecall(
                    controller.getApproveSignature(), beneficiary, uint256(claimedAmount), currencyCt, currencyId
                )
            );
            beneficiary.receiveTokensTo(msg.sender, balanceType, claimedAmount, currencyCt, currencyId, standard);
        }

        // Emit event
        emit ClaimAndTransferToBeneficiaryEvent(msg.sender, beneficiary, balanceType, claimedAmount, currencyCt, currencyId, standard);
    }

    /// @notice Claim reward and stage for later withdrawal
    /// @param currencyCt The address of the concerned currency contract (address(0) == ETH)
    /// @param currencyId The ID of the concerned currency (0 for ETH and ERC20)
    function claimAndStage(address currencyCt, uint256 currencyId)
    public
    {
        // Claim reward
        int256 claimedAmount = _claim(msg.sender, currencyCt, currencyId);

        // Update staged balance
        stagedByWallet[msg.sender].add(claimedAmount, currencyCt, currencyId);

        // Emit event
        emit ClaimAndStageEvent(msg.sender, claimedAmount, currencyCt, currencyId);
    }

    /// @notice Withdraw from staged balance of msg.sender
    /// @param amount The concerned amount
    /// @param currencyCt The address of the concerned currency contract (address(0) == ETH)
    /// @param currencyId The ID of the concerned currency (0 for ETH and ERC20)
    /// @param standard The standard of the token ("" for default registered, "ERC20", "ERC721")
    function withdraw(int256 amount, address currencyCt, uint256 currencyId, string standard)
    public
    {
        // Require that amount is strictly positive
        require(amount.isNonZeroPositiveInt256());

        // Clamp amount to the max given by staged balance
        amount = amount.clampMax(stagedByWallet[msg.sender].get(currencyCt, currencyId));

        // Subtract to per-wallet staged balance
        stagedByWallet[msg.sender].sub(amount, currencyCt, currencyId);

        // Execute transfer
        if (address(0) == currencyCt && 0 == currencyId)
            msg.sender.transfer(uint256(amount));

        else {
            TransferController controller = transferController(currencyCt, standard);
            require(
                address(controller).delegatecall(
                    controller.getDispatchSignature(), this, msg.sender, uint256(amount), currencyCt, currencyId
                )
            );
        }

        // Emit event
        emit WithdrawEvent(msg.sender, amount, currencyCt, currencyId, standard);
    }

    //
    // Functions
    // -----------------------------------------------------------------------------------------------------------------
    function _claim(address wallet, address currencyCt, uint256 currencyId)
    private
    returns (int256)
    {
        require(inUseCurrencies.has(currencyCt, currencyId));
        require(0 < rewardMetaByWallet[wallet].rewardFraction);
        require(block.timestamp >= rewardMetaByWallet[wallet].unlockTime);
        require(
            rewardMetaByWallet[wallet].claimNonceByCurrency[currencyCt][currencyId] < rewardMetaByWallet[wallet].rewardNonce
        );

        // Set stage nonce of currency to the reward nonce
        rewardMetaByWallet[wallet].claimNonceByCurrency[currencyCt][currencyId] = rewardMetaByWallet[wallet].rewardNonce;

        // Calculate claimed amount
        int256 claimedAmount = deposited
        .get(currencyCt, currencyId)
        .mul(SafeMathIntLib.toInt256(rewardMetaByWallet[wallet].rewardFraction))
        .div(ConstantsLib.PARTS_PER());

        // Move from balance to staged
        deposited.sub(claimedAmount, currencyCt, currencyId);

        // Return claimed amount
        return claimedAmount;
    }
}