// SPDX-License-Identifier: BSL-1.1
// Gearbox. Generalized leverage protocol that allows to take leverage and then use it across other DeFi protocols and platforms in a composable way.
// (c) Gearbox.fi, 2021
pragma solidity ^0.7.4;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import {AddressProvider} from "./AddressProvider.sol";
import {ContractsRegister} from "./ContractsRegister.sol";

import {IPoolService} from "../interfaces/IPoolService.sol";
import {ICreditManager} from "../interfaces/ICreditManager.sol";
import {IWETH} from "../interfaces/external/IWETH.sol";
import {IWETHGateway} from "../interfaces/IWETHGateway.sol";

import {Errors} from "../libraries/helpers/Errors.sol";
import {Constants} from "../libraries/helpers/Constants.sol";

import "hardhat/console.sol";

/// @title WETHGateway
/// @notice Used for converting ETH <> WETH
contract WETHGateway is IWETHGateway {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address payable;

    address public wethAddress;
    ContractsRegister internal _contractsRegister;

    /// @dev Checks that pool is registered and underlying token is WETH
    modifier wethPoolOnly(address pool) {
        // Could be optimised by adding internal list of pools
        require(
            _contractsRegister.isPool(pool),
            Errors.WG_DESTINATION_IS_NOT_POOL
        ); // T:[WG-1]

        require(
            IPoolService(pool).underlyingToken() == wethAddress,
            Errors.WG_DESTINATION_IS_NOT_WETH_COMPATIBLE
        ); // T:[WG-2]
        _;
    }

    /// @dev Checks that credit manager is registered and underlying token is WETH
    modifier wethCreditManagerOnly(address creditManager) {
        // Could be optimised by adding internal list of creditManagers

        require(
            _contractsRegister.isCreditManager(creditManager),
            Errors.WG_DESTINATION_IS_NOT_CREDIT_MANAGER
        ); // T:[WG-3]

        require(
            ICreditManager(creditManager).underlyingToken() == wethAddress,
            Errors.WG_DESTINATION_IS_NOT_WETH_COMPATIBLE
        ); // T:[WG-4]

        _;
    }

    /// @dev Checks that credit manager is registered
    modifier creditManagerOnly(address creditManager) {
        // Could be optimised by adding internal list of creditManagers

        require(
            _contractsRegister.isCreditManager(creditManager),
            Errors.WG_DESTINATION_IS_NOT_CREDIT_MANAGER
        ); // T:[WG-3]

        _;
    }

    //
    // CONSTRUCTOR
    //

    /// @dev Constructor
    /// @param addressProvider Address Repository for upgradable contract model
    constructor(address addressProvider) {
        wethAddress = AddressProvider(addressProvider).getWethToken();
        _contractsRegister = ContractsRegister(
            AddressProvider(addressProvider).getContractsRegister()
        );
    }

    /// @dev convert ETH to WETH and add liqudity to pool
    /// @param pool Address of PoolService contract which where user wants to add liquidity. This pool should has WETH as underlying asset
    /// @param onBehalfOf The address that will receive the diesel tokens, same as msg.sender if the user  wants to receive them on his
    ///                   own wallet, or a different address if the beneficiary of diesel tokens is a different wallet
    /// @param referralCode Code used to register the integrator originating the operation, for potential rewards.
    /// 0 if the action is executed directly by the user, without any middle-man
    // SWC-107-Reentrancy: L98 - L112
    function addLiquidityETH(
        address pool,
        address onBehalfOf,
        uint16 referralCode
    )
        external
        payable
        override
        wethPoolOnly(pool) // T:[WG-1, 2]
    {
        IWETH(wethAddress).deposit{value: msg.value}(); // T:[WG-8]

        _checkAllowance(pool, msg.value); // T:[WG-8]
        IPoolService(pool).addLiquidity(msg.value, onBehalfOf, referralCode); // T:[WG-8]
    }

    /// @dev Removes liquidity from pool and convert WETH to ETH
    ///       - burns lp's diesel (LP) tokens
    ///       - returns underlying tokens to lp
    /// @param pool Address of PoolService contract which where user wants to withdraw liquidity. This pool should has WETH as underlying asset
    /// @param amount Amount of tokens to be transfer
    /// @param to Address to transfer liquidity
    // SWC-107-Reentrancy: L120 - L140
    function removeLiquidityETH(
        address pool,
        uint256 amount,
        address payable to
    )
        external
        override
        wethPoolOnly(pool) // T:[WG-1, 2]
    {
        IERC20(IPoolService(pool).dieselToken()).safeTransferFrom(
            msg.sender,
            address(this),
            amount
        ); // T: [WG-9]

        uint256 amountGet = IPoolService(pool).removeLiquidity(
            amount,
            address(this)
        ); // T: [WG-9]
        _unwrapWETH(to, amountGet); // T: [WG-9]
    }

    /// @dev Opens credit account in ETH
    /// @param creditManager Address of credit Manager. Should used WETH as underlying asset
    /// @param onBehalfOf The address that we open credit account. Same as msg.sender if the user wants to open it for  his own wallet,
    ///                   or a different address if the beneficiary is a different wallet
    /// @param leverageFactor Multiplier to borrowers own funds
    /// @param referralCode Code used to register the integrator originating the operation, for potential rewards.
    ///                     0 if the action is executed directly by the user, without any middle-man
    // SWC-107-Reentrancy: L151 - L171
    function openCreditAccountETH(
        address creditManager,
        address payable onBehalfOf,
        uint256 leverageFactor,
        uint256 referralCode
    )
        external
        payable
        override
        wethCreditManagerOnly(creditManager) // T:[WG-3, 4]
    {
        _checkAllowance(creditManager, msg.value); // T:[WG-10]

        IWETH(wethAddress).deposit{value: msg.value}(); // T:[WG-10]
        ICreditManager(creditManager).openCreditAccount(
            msg.value,
            onBehalfOf,
            leverageFactor,
            referralCode
        ); // T:[WG-10]
    }

    /// @dev Repays credit account in ETH
    ///       - transfer borrowed money with interest + fee from borrower account to pool
    ///       - transfer all assets to "to" account
    /// @param creditManager Address of credit Manager. Should used WETH as underlying asset
    /// @param to Address to send credit account assets
    // SWC-107-Reentrancy: L179 - L199
    function repayCreditAccountETH(address creditManager, address to)
        external
        payable
        override
        wethCreditManagerOnly(creditManager) // T:[WG-3, 4]
    {
        uint256 amount = msg.value; // T: [WG-11]

        IWETH(wethAddress).deposit{value: amount}(); // T: [WG-11]
//        address pool = ICreditManager(creditManager).poolService(); // T: [WG-11]
        _checkAllowance(creditManager, amount); // T: [WG-11]

        // This function is protected from reentrant attack
        uint256 repayAmount = ICreditManager(creditManager)
        .repayCreditAccountETH(msg.sender, to); // T: [WG-11, 13]

        if (amount > repayAmount) {
            IWETH(wethAddress).withdraw(amount.sub(repayAmount));
            msg.sender.sendValue(amount.sub(repayAmount)); // T: [WG-12]
        }
    }

    function addCollateralETH(address creditManager, address onBehalfOf)
        external
        payable
        override
        creditManagerOnly(creditManager)
    {
        uint256 amount = msg.value; // T:[WG-14]

        IWETH(wethAddress).deposit{value: amount}(); // T:[WG-14]
        _checkAllowance(creditManager, amount); // T:[WG-14]
        ICreditManager(creditManager).addCollateral(
            onBehalfOf,
            wethAddress,
            amount
        ); // T:[WG-14]
    }

    /// @dev Converts WETH to ETH, it's used when credit manager sends tokens, and one of them is WETH
    function unwrapWETH(address to, uint256 amount)
        external
        override
        creditManagerOnly(msg.sender) // T:[WG-5]
    {
        _unwrapWETH(to, amount); // T: [WG-7]
    }

    function _unwrapWETH(address to, uint256 amount) internal {
        IWETH(wethAddress).withdraw(amount); // T: [WG-7]
        payable(to).sendValue(amount); // T: [WG-7]
    }

    function _checkAllowance(address spender, uint256 amount) internal {
        if (IERC20(wethAddress).allowance(address(this), spender) < amount) {
            IERC20(wethAddress).approve(spender, Constants.MAX_INT);
        }
    }

    /// @dev Only WETH contract is allowed to transfer ETH here. Prevent other addresses to send Ether to this contract.
    receive() external payable {
        require(
            msg.sender == address(wethAddress),
            Errors.WG_RECEIVE_IS_NOT_ALLOWED
        ); // T:[WG-6]
    }
}
