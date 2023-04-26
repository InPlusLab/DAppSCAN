// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.9;

import { IERC20Metadata } from '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import { ProxyAdmin } from '@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol';

import { IUniswapV3Pool } from '@uniswap/v3-core-0.8-support/contracts/interfaces/IUniswapV3Pool.sol';
import { IUniswapV3Factory } from '@uniswap/v3-core-0.8-support/contracts/interfaces/IUniswapV3Factory.sol';

import { ClearingHouseDeployer } from './clearinghouse/ClearingHouseDeployer.sol';
import { InsuranceFundDeployer } from './insurancefund/InsuranceFundDeployer.sol';
import { VQuoteDeployer } from './tokens/VQuoteDeployer.sol';
import { VTokenDeployer } from './tokens/VTokenDeployer.sol';
import { VToken } from './tokens/VToken.sol';
import { VPoolWrapperDeployer } from './wrapper/VPoolWrapperDeployer.sol';

import { IClearingHouse } from '../interfaces/IClearingHouse.sol';
import { IClearingHouseStructures } from '../interfaces/clearinghouse/IClearingHouseStructures.sol';
import { IInsuranceFund } from '../interfaces/IInsuranceFund.sol';
import { IOracle } from '../interfaces/IOracle.sol';
import { IVQuote } from '../interfaces/IVQuote.sol';
import { IVPoolWrapper } from '../interfaces/IVPoolWrapper.sol';
import { IVToken } from '../interfaces/IVToken.sol';

import { AddressHelper } from '../libraries/AddressHelper.sol';
import { PriceMath } from '../libraries/PriceMath.sol';

import { SettlementTokenOracle } from '../oracles/SettlementTokenOracle.sol';
import { Governable } from '../utils/Governable.sol';

import { UNISWAP_V3_FACTORY_ADDRESS, UNISWAP_V3_DEFAULT_FEE_TIER } from '../utils/constants.sol';

contract RageTradeFactory is
    Governable,
    ClearingHouseDeployer,
    InsuranceFundDeployer,
    VQuoteDeployer,
    VPoolWrapperDeployer,
    VTokenDeployer
{
    using AddressHelper for address;
    using PriceMath for uint256;

    IVQuote public immutable vQuote;
    IClearingHouse public immutable clearingHouse;
    // IInsuranceFund public insuranceFund; // stored in ClearingHouse, replacable from there

    event PoolInitialized(IUniswapV3Pool vPool, IVToken vToken, IVPoolWrapper vPoolWrapper);

    /// @notice Sets up the protocol by deploying necessary core contracts
    /// @dev Need to deploy logic contracts for ClearingHouse, VPoolWrapper, InsuranceFund prior to this
    constructor(
        address clearingHouseLogicAddress,
        address _vPoolWrapperLogicAddress,
        address insuranceFundLogicAddress,
        IERC20Metadata settlementToken
    ) VPoolWrapperDeployer(_vPoolWrapperLogicAddress) {
        proxyAdmin = _deployProxyAdmin();
        proxyAdmin.transferOwnership(msg.sender);

        // deploys VQuote contract at an address which has most significant nibble as "f"
        vQuote = _deployVQuote(settlementToken.decimals());

        // deploys InsuranceFund proxy
        IInsuranceFund insuranceFund = _deployProxyForInsuranceFund(insuranceFundLogicAddress);

        SettlementTokenOracle settlementTokenOracle = new SettlementTokenOracle();

        // deploys a proxy for ClearingHouse, and initialize it as well
        clearingHouse = _deployProxyForClearingHouseAndInitialize(
            ClearingHouseDeployer.DeployClearingHouseParams(
                clearingHouseLogicAddress,
                settlementToken,
                settlementTokenOracle,
                insuranceFund,
                vQuote
            )
        );
        clearingHouse.transferGovernance(msg.sender);
        clearingHouse.transferTeamMultisig(msg.sender);

        _initializeInsuranceFund(insuranceFund, settlementToken, clearingHouse);
    }

    struct InitializePoolParams {
        VTokenDeployer.DeployVTokenParams deployVTokenParams;
        IClearingHouseStructures.PoolSettings poolInitialSettings;
        uint24 liquidityFeePips;
        uint24 protocolFeePips;
        uint16 slotsToInitialize;
    }

    /// @notice Sets up a new Rage Trade Pool by deploying necessary contracts
    /// @dev An already deployed oracle contract address (implementing IOracle) is needed prior to using this
    /// @param initializePoolParams parameters for initializing the pool
    function initializePool(InitializePoolParams calldata initializePoolParams) external onlyGovernance {
        // as an argument to vtoken constructer and make wrapper variable as immutable.
        // this will save sload on all vtoken mints (swaps liqudity adds).
        // STEP 1: Deploy the virtual token ERC20, such that it will be token0
        IVToken vToken = _deployVToken(initializePoolParams.deployVTokenParams);

        // STEP 2: Deploy vPool (token0=vToken, token1=vQuote) on actual uniswap
        IUniswapV3Pool vPool = _createUniswapV3Pool(vToken);

        // STEP 3: Initialize the price on the vPool
        vPool.initialize(
            initializePoolParams
                .poolInitialSettings
                .oracle
                .getTwapPriceX128(initializePoolParams.poolInitialSettings.twapDuration)
                .toSqrtPriceX96()
        );

        vPool.increaseObservationCardinalityNext(initializePoolParams.slotsToInitialize);

        // STEP 4: Deploys a proxy for the wrapper contract for the vPool, and initialize it as well
        IVPoolWrapper vPoolWrapper = _deployProxyForVPoolWrapperAndInitialize(
            IVPoolWrapper.InitializeVPoolWrapperParams(
                clearingHouse,
                vToken,
                vQuote,
                vPool,
                initializePoolParams.liquidityFeePips,
                initializePoolParams.protocolFeePips
            )
        );

        // STEP 5: Authorize vPoolWrapper in vToken and vQuote, for minting/burning whenever needed
        vQuote.authorize(address(vPoolWrapper));
        vToken.setVPoolWrapper(address(vPoolWrapper));
        clearingHouse.registerPool(
            IClearingHouseStructures.Pool(vToken, vPool, vPoolWrapper, initializePoolParams.poolInitialSettings)
        );

        emit PoolInitialized(vPool, vToken, vPoolWrapper);
    }

    function _createUniswapV3Pool(IVToken vToken) internal returns (IUniswapV3Pool) {
        return
            IUniswapV3Pool(
                IUniswapV3Factory(UNISWAP_V3_FACTORY_ADDRESS).createPool(
                    address(vQuote),
                    address(vToken),
                    UNISWAP_V3_DEFAULT_FEE_TIER
                )
            );
    }

    function _isIVTokenAddressGood(address addr) internal view virtual override returns (bool) {
        uint32 poolId = addr.truncate();
        return
            // Zero element is considered empty in Uint32L8Array.sol
            poolId != 0 &&
            // vToken should be token0 and vQuote should be token1 in UniswapV3Pool
            (uint160(addr) < uint160(address(vQuote))) &&
            // there should not be a collision in poolIds
            clearingHouse.isPoolIdAvailable(poolId);
    }
}
