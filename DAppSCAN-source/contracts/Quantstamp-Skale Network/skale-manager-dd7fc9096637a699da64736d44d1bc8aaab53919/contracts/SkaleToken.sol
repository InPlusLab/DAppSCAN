// SPDX-License-Identifier: AGPL-3.0-only

/*
    SkaleToken.sol - SKALE Manager
    Copyright (C) 2018-Present SKALE Labs
    @author Artem Payvin

    SKALE Manager is free software: you can redistribute it and/or modify
    it under the terms of the GNU Affero General Public License as published
    by the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    SKALE Manager is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU Affero General Public License for more details.

    You should have received a copy of the GNU Affero General Public License
    along with SKALE Manager.  If not, see <https://www.gnu.org/licenses/>.
*/

pragma solidity 0.8.11;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@skalenetwork/skale-manager-interfaces/delegation/IDelegatableToken.sol";
import "@skalenetwork/skale-manager-interfaces/IMintableToken.sol";
import "@skalenetwork/skale-manager-interfaces/delegation/IPunisher.sol";
import "@skalenetwork/skale-manager-interfaces/delegation/ITokenState.sol";
import "@skalenetwork/skale-manager-interfaces/delegation/IDelegationController.sol";
import "@skalenetwork/skale-manager-interfaces/delegation/ILocker.sol";

import "./thirdparty/openzeppelin/ERC777.sol";

import "./Permissions.sol";


/**
 * @title SkaleToken
 * @dev Contract defines the SKALE token and is based on ERC777 token
 * implementation.
 */
contract SkaleToken is ERC777, Permissions, ReentrancyGuard, IDelegatableToken, IMintableToken {
    using SafeMath for uint;

    string public constant NAME = "SKALE";

    string public constant SYMBOL = "SKL";

    uint public constant DECIMALS = 18;

    uint public constant CAP = 7 * 1e9 * (10 ** DECIMALS); // the maximum amount of tokens that can ever be created

    constructor(address contractsAddress, address[] memory defOps)
    ERC777("SKALE", "SKL", defOps)
    {
        Permissions.initialize(contractsAddress);
    }

    /**
     * @dev Allows Owner or SkaleManager to mint an amount of tokens and 
     * transfer minted tokens to a specified address.
     * 
     * Returns whether the operation is successful.
     * 
     * Requirements:
     * 
     * - Mint must not exceed the total supply.
     */
    function mint(
        address account,
        uint256 amount,
        bytes calldata userData,
        bytes calldata operatorData
    )
        external
        override
        allow("SkaleManager")
        //onlyAuthorized
        returns (bool)
    {
        require(amount <= CAP.sub(totalSupply()), "Amount is too big");
        _mint(
            account,
            amount,
            userData,
            operatorData
        );

        return true;
    }

    /**
     * @dev See {IDelegatableToken-getAndUpdateDelegatedAmount}.
     */
    function getAndUpdateDelegatedAmount(address wallet) external override returns (uint) {
        return IDelegationController(contractManager.getContract("DelegationController"))
            .getAndUpdateDelegatedAmount(wallet);
    }

    /**
     * @dev See {IDelegatableToken-getAndUpdateSlashedAmount}.
     */
    function getAndUpdateSlashedAmount(address wallet) external override returns (uint) {
        return ILocker(contractManager.getContract("Punisher")).getAndUpdateLockedAmount(wallet);
    }

    /**
     * @dev See {IDelegatableToken-getAndUpdateLockedAmount}.
     */
    function getAndUpdateLockedAmount(address wallet) public override returns (uint) {
        return ILocker(contractManager.getContract("TokenState")).getAndUpdateLockedAmount(wallet);
    }

    // internal

    function _beforeTokenTransfer(
        address, // operator
        address from,
        address, // to
        uint256 tokenId)
        internal override
    {
        uint locked = getAndUpdateLockedAmount(from);
        if (locked > 0) {
            require(balanceOf(from) >= locked.add(tokenId), "Token should be unlocked for transferring");
        }
    }

    function _callTokensToSend(
        address operator,
        address from,
        address to,
        uint256 amount,
        bytes memory userData,
        bytes memory operatorData
    ) internal override nonReentrant {
        super._callTokensToSend(operator, from, to, amount, userData, operatorData);
    }

    function _callTokensReceived(
        address operator,
        address from,
        address to,
        uint256 amount,
        bytes memory userData,
        bytes memory operatorData,
        bool requireReceptionAck
    ) internal override nonReentrant {
        super._callTokensReceived(operator, from, to, amount, userData, operatorData, requireReceptionAck);
    }

    // we have to override _msgData() and _msgSender() functions because of collision in Context and ContextUpgradeable

    function _msgData() internal view override(Context, ContextUpgradeable) returns (bytes memory) {
        return Context._msgData();
    }

    function _msgSender() internal view override(Context, ContextUpgradeable) returns (address) {
        return Context._msgSender();
    }
}
