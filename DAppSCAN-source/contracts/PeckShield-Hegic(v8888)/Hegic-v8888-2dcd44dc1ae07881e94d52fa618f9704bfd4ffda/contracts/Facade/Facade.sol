pragma solidity 0.8.6;

/**
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Hegic
 * Copyright (C) 2021 Hegic Protocol
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 **/

import "../Interfaces/Interfaces.sol";

/**
 * @author 0mllwntrmt3
 * @title Hegic Protocol V8888 Facade Contract
 * @notice The contract that calculates the options prices,
 * conducts the process of buying options, converts the premiums
 * into the token that the pool is denominated in and grants
 * permissions to the contracts such as GSN (Gas Station Network).
 **/

contract Facade is Ownable {
    using SafeERC20 for IERC20;

    IWETH public immutable WETH;
    IUniswapV2Router01 public immutable exchange;
    address public _trustedForwarder;

    constructor(
        IWETH weth,
        IUniswapV2Router01 router,
        address trustedForwarder
    ) {
        WETH = weth;
        exchange = router;
        _trustedForwarder = trustedForwarder;
    }

    /**
     * @notice Used for calculating the option price (the premium) and using
     * the swap router (if needed) to convert the tokens with which the user
     * pays the premium into the token in which the pool is denominated.
     * @param period The option period
     * @param amount The option size
     * @param strike The option strike
     * @param total The total premium
     * @param baseTotal The part of the premium that
     * is distributed among the liquidity providers
     * @param settlementFee The part of the premium that
     * is distributed among the HEGIC staking participants
     **/
    function getOptionPrice(
        IHegicPool pool,
        uint256 period,
        uint256 amount,
        uint256 strike,
        address[] calldata swappath
    )
        public
        view
        returns (
            uint256 total,
            uint256 baseTotal,
            uint256 settlementFee,
            uint256 premium
        )
    {
        (uint256 _baseTotal, uint256 baseSettlementFee, uint256 basePremium) =
            getBaseOptionCost(pool, period, amount, strike);
        if (swappath.length > 1)
            total = exchange.getAmountsIn(_baseTotal, swappath)[0];
        else total = _baseTotal;

        baseTotal = _baseTotal;
        settlementFee = (total * baseSettlementFee) / baseTotal;
        premium = (total * basePremium) / baseTotal;
    }

    /**
     * @notice Used for calculating the option price (the premium)
     * in the token in which the pool is denominated.
     * @param period The option period
     * @param amount The option size
     * @param strike The option strike
     **/
    function getBaseOptionCost(
        IHegicPool pool,
        uint256 period,
        uint256 amount,
        uint256 strike
    )
        public
        view
        returns (
            uint256 total,
            uint256 settlementFee,
            uint256 premium
        )
    {
        (settlementFee, premium) = pool.calculateTotalPremium(
            period,
            amount,
            strike
        );
        total = premium + settlementFee;
    }

    /**
     * @notice Used for approving the pools contracts addresses.
     **/
    function poolApprove(IHegicPool pool) external {
        pool.token().approve(address(pool), type(uint256).max);
    }

    /**
     * @notice Used for buying the option contract and converting
     * the buyer's tokens (the total premium) into the token
     * in which the pool is denominated.
     * @param period The option period
     * @param amount The option size
     * @param strike The option strike
     **/
    function createOption(
        IHegicPool pool,
        uint256 period,
        uint256 amount,
        uint256 strike,
        address[] calldata swappath
    ) external payable {
        address buyer = _msgSender();
        (uint256 optionPrice, uint256 rawOptionPrice, , ) =
            getOptionPrice(pool, period, amount, strike, swappath);
        IERC20 paymentToken = IERC20(swappath[0]);
        paymentToken.safeTransferFrom(buyer, address(this), optionPrice);
        if (swappath.length > 1) {
            if (
                paymentToken.allowance(address(this), address(exchange)) <
                optionPrice
            ) paymentToken.approve(address(exchange), type(uint256).max);

            exchange.swapTokensForExactTokens(
                rawOptionPrice,
                optionPrice,
                swappath,
                address(this),
                block.timestamp
            );
        }
        pool.sellOption(buyer, period, amount, strike);
    }

    /**
     * @notice Used for converting the liquidity provider's Ether (ETH)
     * into Wrapped Ether (WETH) and providing the funds into the pool.
     * @param hedged The liquidity tranche type: hedged or unhedged (classic)
     **/
    function provideEthToPool(
        IHegicPool pool,
        bool hedged,
        uint256 minShare
    ) external payable returns (uint256) {
        WETH.deposit{value: msg.value}();
        if (WETH.allowance(address(this), address(pool)) < msg.value)
            WETH.approve(address(pool), type(uint256).max);
        return pool.provideFrom(msg.sender, msg.value, hedged, minShare);
    }

    /**
     * @notice Unlocks the array of options.
     * @param optionIDs The array of options
     **/
    function unlockAll(IHegicPool pool, uint256[] calldata optionIDs) external {
        uint256 arrayLength = optionIDs.length;
        for (uint256 i = 0; i < arrayLength; i++) {
            pool.unlock(optionIDs[i]);
        }
    }

    /**
     * @notice Used for granting the GSN (Gas Station Network) contract
     * the permission to pay the gas (transaction) fees for the users.
     * @param forwarder GSN (Gas Station Network) contract address
     **/
    function isTrustedForwarder(address forwarder) public view returns (bool) {
        return forwarder == _trustedForwarder;
    }

    function claimAllStakingProfits(
        IHegicStaking[] calldata stakings,
        address account
    ) external {
        uint256 arrayLength = stakings.length;
        for (uint256 i = 0; i < arrayLength; i++) {
            IHegicStaking s = stakings[i];
            if (s.profitOf(account) > 0) s.claimProfits(account);
        }
    }

    function _msgSender() internal view override returns (address signer) {
        signer = msg.sender;
        if (msg.data.length >= 20 && isTrustedForwarder(signer)) {
            assembly {
                signer := shr(96, calldataload(sub(calldatasize(), 20)))
            }
        }
    }
}
