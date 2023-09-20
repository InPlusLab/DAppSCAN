// SPDX-License-Identifier: BSL-1.1
// Gearbox. Generalized leverage protocol that allows to take leverage and then use it across other DeFi protocols and platforms in a composable way.
// (c) Gearbox.fi, 2021
pragma solidity ^0.7.4;
pragma experimental ABIEncoderV2;

import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";
import {PercentageMath} from "../libraries/math/PercentageMath.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ICreditAccount} from "../interfaces/ICreditAccount.sol";
import {ICreditManager} from "../interfaces/ICreditManager.sol";
import {CreditManager} from "../credit/CreditManager.sol";
import {IPoolService} from "../interfaces/IPoolService.sol";
import {ICreditFilter} from "../interfaces/ICreditFilter.sol";
import {IPriceOracle} from "../interfaces/IPriceOracle.sol";

import {AddressProvider} from "./AddressProvider.sol";
import {ContractsRegister} from "./ContractsRegister.sol";

import {DataTypes} from "../libraries/data/Types.sol";
import {Errors} from "../libraries/helpers/Errors.sol";

/// @title Data compressor
/// @notice Collects data from different contracts to send it to dApp
/// Do not use for data from data compressor for state-changing functions
contract DataCompressor {
    using SafeMath for uint256;
    using PercentageMath for uint256;
    AddressProvider public addressProvider;
    ContractsRegister public immutable contractsRegister;
    address public immutable WETHToken;

    /// @dev Allows provide data for registered pools only to eliminated usage for non-gearbox contracts
    modifier registeredPoolOnly(address pool) {
        // Could be optimised by adding internal list of pools
        require(
            contractsRegister.isPool(pool),
            Errors.WG_DESTINATION_IS_NOT_POOL
        ); // T:[WG-1]

        _;
    }

    /// @dev Allows provide data for registered credit managers only to eliminated usage for non-gearbox contracts
    modifier registeredCreditManagerOnly(address creditManager) {
        // Could be optimised by adding internal list of creditManagers
        require(
            contractsRegister.isCreditManager(creditManager),
            Errors.WG_DESTINATION_IS_NOT_CREDIT_MANAGER
        ); // T:[WG-3]

        _;
    }

    constructor(address _addressProvider) {
        addressProvider = AddressProvider(_addressProvider);
        contractsRegister = ContractsRegister(
            addressProvider.getContractsRegister()
        );
        WETHToken = addressProvider.getWethToken();
    }

    /// @dev Returns CreditAccountData for all opened account for particluar borrower
    /// @param borrower Borrower address
    function getCreditAccountList(address borrower)
        external
        view
        returns (DataTypes.CreditAccountData[] memory)
    {
        // Counts how much opened account a borrower has
        // SWC-135-Code With No Effects: L73
        uint256 count = 0;
        for (
            uint256 i = 0;
            i < contractsRegister.getCreditManagersCount();
            i++
        ) {
            address creditManager = contractsRegister.creditManagers(i);
            if (
                ICreditManager(creditManager).hasOpenedCreditAccount(borrower)
            ) {
                count++;
            }
        }


            DataTypes.CreditAccountData[] memory result
         = new DataTypes.CreditAccountData[](count);

        // Get data & fill the array
        count = 0;
        for (
            uint256 i = 0;
            i < contractsRegister.getCreditManagersCount();
            i++
        ) {
            address creditManager = contractsRegister.creditManagers(i);
            if (
                ICreditManager(creditManager).hasOpenedCreditAccount(borrower)
            ) {
                result[count] = getCreditAccountData(creditManager, borrower);
                count++;
            }
        }
        return result;
    }

    function hasOpenedCreditAccount(address _creditManager, address borrower)
        public
        view
        registeredCreditManagerOnly(_creditManager)
        returns (bool)
    {
        ICreditManager creditManager = ICreditManager(_creditManager);
        return creditManager.hasOpenedCreditAccount(borrower);
    }

    /// @dev Returns CreditAccountData for particular account for creditManager and borrower
    /// @param _creditManager Credit manager address
    /// @param borrower Borrower address
    function getCreditAccountData(address _creditManager, address borrower)
        public
        view
        registeredCreditManagerOnly(_creditManager)
        returns (DataTypes.CreditAccountData memory)
    {
        ICreditManager creditManager = ICreditManager(_creditManager);
        address creditAccount = creditManager.getCreditAccountOrRevert(
            borrower
        );

        DataTypes.CreditAccountData memory result;

        result.borrower = borrower;
        result.creditManager = _creditManager;
        result.addr = creditAccount;

        ICreditFilter creditFilter = ICreditFilter(
            ICreditManager(creditManager).creditFilter()
        );

        result.underlyingToken = creditFilter.underlyingToken();

        result.totalValue = creditFilter.calcTotalValue(creditAccount);

        result.healthFactor = creditFilter.calcCreditAccountHealthFactor(
            creditAccount
        );

        address pool = creditManager.poolService();
        result.borrowRate = IPoolService(pool).borrowAPY_RAY();

        uint256 allowedTokenCount = creditFilter.allowedTokensCount();

        result.balances = new DataTypes.TokenBalance[](allowedTokenCount);
        for (uint256 i = 0; i < allowedTokenCount; i++) {
            DataTypes.TokenBalance memory balance;
            (balance.token, balance.balance, , ) = creditFilter
            .getCreditAccountTokenById(creditAccount, i);
            result.balances[i] = balance;
        }

        result.borrowedAmountPlusInterest = creditFilter
        .calcCreditAccountAccruedInterest(creditAccount);

        return result;
    }

    /// @dev Returns CreditAccountDataExtendeds for particular account for creditManager and borrower
    /// @param creditManager Credit manager address
    /// @param borrower Borrower address
    function getCreditAccountDataExtended(
        address creditManager,
        address borrower
    )
        external
        view
        registeredCreditManagerOnly(creditManager)
        returns (DataTypes.CreditAccountDataExtended memory)
    {
        DataTypes.CreditAccountDataExtended memory result;
        DataTypes.CreditAccountData memory data = getCreditAccountData(
            creditManager,
            borrower
        );

        result.addr = data.addr;
        result.borrower = data.borrower;
        result.creditManager = data.creditManager;
        result.underlyingToken = data.underlyingToken;
        result.borrowedAmountPlusInterest = data.borrowedAmountPlusInterest;
        result.totalValue = data.totalValue;
        result.healthFactor = data.healthFactor;
        result.borrowRate = data.borrowRate;
        result.balances = data.balances;

        address creditAccount = ICreditManager(creditManager)
        .getCreditAccountOrRevert(borrower);

        result.borrowedAmount = ICreditAccount(creditAccount).borrowedAmount();
        result.cumulativeIndexAtOpen = ICreditAccount(creditAccount)
        .cumulativeIndexAtOpen();

        result.since = ICreditAccount(creditAccount).since();
        result.repayAmount = ICreditManager(creditManager).calcRepayAmount(
            borrower,
            false
        );
        result.liquidationAmount = ICreditManager(creditManager)
        .calcRepayAmount(borrower, true);

        (, , , , uint256 loss) = CreditManager(creditManager)
        ._calcClosePayments(creditAccount, data.totalValue, false);

        result.canBeClosed = loss == 0;

        return result;
    }

    /// @dev Returns all credit managers data + hasOpendAccount flag for bborrower
    /// @param borrower Borrower address
    function getCreditManagersList(address borrower)
        external
        view
        returns (DataTypes.CreditManagerData[] memory)
    {
        uint256 creditManagersCount = contractsRegister
        .getCreditManagersCount();


            DataTypes.CreditManagerData[] memory result
         = new DataTypes.CreditManagerData[](creditManagersCount);

        for (uint256 i = 0; i < creditManagersCount; i++) {
            address creditManager = contractsRegister.creditManagers(i);
            result[i] = getCreditManagerData(creditManager, borrower);
        }

        return result;
    }

    /// @dev Returns CreditManagerData for particular _creditManager and
    /// set flg hasOpenedCreditAccount for provided borrower
    /// @param _creditManager CreditManager address
    /// @param borrower Borrower address
    function getCreditManagerData(address _creditManager, address borrower)
        public
        view
        registeredCreditManagerOnly(_creditManager)
        returns (DataTypes.CreditManagerData memory)
    {
        ICreditManager creditManager = ICreditManager(_creditManager);
        DataTypes.CreditManagerData memory result;

        result.addr = _creditManager;
        result.hasAccount = creditManager.hasOpenedCreditAccount(borrower);

        ICreditFilter creditFilter = ICreditFilter(
            ICreditManager(creditManager).creditFilter()
        );

        result.underlyingToken = creditFilter.underlyingToken();
        result.isWETH = result.underlyingToken == WETHToken;

        IPoolService pool = IPoolService(creditManager.poolService());
        result.canBorrow = pool.creditManagersCanBorrow(_creditManager);
        result.borrowRate = pool.borrowAPY_RAY();
        result.availableLiquidity = pool.availableLiquidity();
        result.minAmount = creditManager.minAmount();
        result.maxAmount = creditManager.maxAmount();
        result.maxLeverageFactor = creditManager.maxLeverageFactor();

        uint256 allowedTokenCount = creditFilter.allowedTokensCount();

        result.allowedTokens = new address[](allowedTokenCount);
        for (uint256 i = 0; i < allowedTokenCount; i++) {
            result.allowedTokens[i] = creditFilter.allowedTokens(i);
        }

        uint256 allowedContractsCount = creditFilter.allowedContractsCount();

        result.adapters = new DataTypes.ContractAdapter[](
            allowedContractsCount
        );
        for (uint256 i = 0; i < allowedContractsCount; i++) {
            DataTypes.ContractAdapter memory adapter;
            adapter.allowedContract = creditFilter.allowedContracts(i);
            adapter.adapter = creditFilter.contractToAdapter(
                adapter.allowedContract
            );
            result.adapters[i] = adapter;
        }

        return result;
    }

    /// @dev Returns PoolData for particulr pool
    /// @param _pool Pool address
    function getPoolData(address _pool)
        public
        view
        registeredPoolOnly(_pool)
        returns (DataTypes.PoolData memory)
    {
        DataTypes.PoolData memory result;
        IPoolService pool = IPoolService(_pool);

        result.addr = _pool;
        result.expectedLiquidity = pool.expectedLiquidity();
        result.expectedLiquidityLimit = pool.expectedLiquidityLimit();
        result.availableLiquidity = pool.availableLiquidity();
        result.totalBorrowed = pool.totalBorrowed();
        result.dieselRate_RAY = pool.getDieselRate_RAY();
        result.linearCumulativeIndex = pool.calcLinearCumulative_RAY();
        result.borrowAPY_RAY = pool.borrowAPY_RAY();
        result.underlyingToken = pool.underlyingToken();
        result.dieselToken = pool.dieselToken();
        result.dieselRate_RAY = pool.getDieselRate_RAY();
        result.withdrawFee = pool.withdrawFee();
        result.isWETH = result.underlyingToken == WETHToken;
        result.timestampLU = pool._timestampLU();
        result.cumulativeIndex_RAY = pool._cumulativeIndex_RAY();

        uint256 dieselSupply = IERC20(result.dieselToken).totalSupply();
        uint256 totalLP = pool.fromDiesel(dieselSupply);
        result.depositAPY_RAY = totalLP == 0
            ? result.borrowAPY_RAY
            : result
            .borrowAPY_RAY
            .mul(result.totalBorrowed)
            .percentMul(
                PercentageMath.PERCENTAGE_FACTOR.sub(result.withdrawFee)
            ).div(totalLP);

        return result;
    }

    /// @dev Returns PoolData for all registered pools
    function getPoolsList()
        external
        view
        returns (DataTypes.PoolData[] memory)
    {
        uint256 poolsCount = contractsRegister.getPoolsCount();

        DataTypes.PoolData[] memory result = new DataTypes.PoolData[](
            poolsCount
        );

        for (uint256 i = 0; i < poolsCount; i++) {
            address pool = contractsRegister.pools(i);
            result[i] = getPoolData(pool);
        }

        return result;
    }

    /// @dev Returns compressed token data for particular token.
    /// Be careful, it can be reverted for non-standart tokens which has no "symbol" method for example
    function getTokenData(address addr)
        public
        view
        returns (DataTypes.TokenInfo memory)
    {
        DataTypes.TokenInfo memory result;
        ERC20 token = ERC20(addr);
        result.addr = addr;
        result.decimals = token.decimals();
        result.symbol = token.symbol();

        return result;
    }

    /// @dev Returns adapter address for particular creditManager and protocol
    function getAdapter(address _creditManager, address _allowedContract)
        external
        view
        registeredCreditManagerOnly(_creditManager)
        returns (address)
    {
        return
            ICreditManager(_creditManager).creditFilter().contractToAdapter(
                _allowedContract
            );
    }

    function calcExpectedHf(
        address _creditManager,
        address borrower,
        uint256[] memory balances
    )
        external
        view
        registeredCreditManagerOnly(_creditManager)
        returns (uint256)
    {
        ICreditManager creditManager = ICreditManager(_creditManager);
        address creditAccount = creditManager.getCreditAccountOrRevert(
            borrower
        );

        ICreditFilter creditFilter = ICreditFilter(
            creditManager.creditFilter()
        );

        IPriceOracle priceOracle = IPriceOracle(creditFilter.priceOracle());
        uint256 tokenLength = creditFilter.allowedTokensCount();
        require(balances.length == tokenLength, "Incorrect balances size");

        uint256 total = 0;
        address underlyingToken = creditManager.underlyingToken();

        for (uint256 i = 0; i < tokenLength; i++) {
            {
                total = total.add(
                    priceOracle
                    .convert(
                        balances[i],
                        creditFilter.allowedTokens(i),
                        underlyingToken
                    ).mul(
                        creditFilter.liquidationThresholds(
                            creditFilter.allowedTokens(i)
                        )
                    )
                );
            }
        }

        return
            total.div(
                creditFilter.calcCreditAccountAccruedInterest(creditAccount)
            );
    }
}
