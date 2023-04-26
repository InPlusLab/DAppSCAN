// SPDX-License-Identifier: Apache-2.0

/**
 *Submitted for verification at polygonscan.com on 2021-08-27
*/

/**
 *Submitted for verification at polygonscan.com on 2021-08-12
*/

// SPDX-License-Identifier: MIT

import "./UChildERC20.sol";
import "./libraries/admin/Pausable.sol";
import "./libraries/admin/Rescuable.sol";
import "./libraries/admin/Blacklistable.sol";

// File: contracts/UChildAdministrableERC20.sol

pragma solidity 0.6.12;

contract UChildAdministrableERC20 is
    UChildERC20,
    Blacklistable,
    Pausable,
    Rescuable
{
    
    function _msgSender()
        internal
        override(Context, UChildERC20)
        view
        returns (address payable sender)
    {
        return ContextMixin.msgSender();
    }

    function withdraw(uint256 amount)
        external
        override
        notBlacklisted(_msgSender())
    {
        _burn(_msgSender(), amount);
    }

    function transfer(address recipient, uint256 amount)
        external
        override
        whenNotPaused
        notBlacklisted(_msgSender())
        notBlacklisted(recipient)
        returns (bool)
    {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function approve(address spender, uint256 amount)
        external
        override
        whenNotPaused
        notBlacklisted(_msgSender())
        notBlacklisted(spender)
        returns (bool)
    {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    )
        external
        override
        whenNotPaused
        notBlacklisted(_msgSender())
        notBlacklisted(sender)
        notBlacklisted(recipient)
        returns (bool)
    {
        _transferFrom(sender, recipient, amount);
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue)
        external
        override
        whenNotPaused
        notBlacklisted(_msgSender())
        notBlacklisted(spender)
        returns (bool)
    {
        _increaseAllowance(_msgSender(), spender, addedValue);
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue)
        external
        override
        whenNotPaused
        notBlacklisted(_msgSender())
        notBlacklisted(spender)
        returns (bool)
    {
        _decreaseAllowance(_msgSender(), spender, subtractedValue);
        return true;
    }

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    )
        external
        override
        whenNotPaused
        notBlacklisted(owner)
        notBlacklisted(spender)
    {
        _permit(owner, spender, value, deadline, v, r, s);
    }

    function transferWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external override whenNotPaused notBlacklisted(from) notBlacklisted(to) {
        _transferWithAuthorization(
            from,
            to,
            value,
            validAfter,
            validBefore,
            nonce,
            v,
            r,
            s
        );
    }

    function approveWithAuthorization(
        address owner,
        address spender,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    )
        external
        override
        whenNotPaused
        notBlacklisted(owner)
        notBlacklisted(spender)
    {
        _approveWithAuthorization(
            owner,
            spender,
            value,
            validAfter,
            validBefore,
            nonce,
            v,
            r,
            s
        );
    }

    function increaseAllowanceWithAuthorization(
        address owner,
        address spender,
        uint256 increment,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    )
        external
        override
        whenNotPaused
        notBlacklisted(owner)
        notBlacklisted(spender)
    {
        _increaseAllowanceWithAuthorization(
            owner,
            spender,
            increment,
            validAfter,
            validBefore,
            nonce,
            v,
            r,
            s
        );
    }

    function decreaseAllowanceWithAuthorization(
        address owner,
        address spender,
        uint256 decrement,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    )
        external
        override
        whenNotPaused
        notBlacklisted(owner)
        notBlacklisted(spender)
    {
        _decreaseAllowanceWithAuthorization(
            owner,
            spender,
            decrement,
            validAfter,
            validBefore,
            nonce,
            v,
            r,
            s
        );
    }

    function withdrawWithAuthorization(
        address owner,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external override whenNotPaused notBlacklisted(owner) {
        _withdrawWithAuthorization(
            owner,
            value,
            validAfter,
            validBefore,
            nonce,
            v,
            r,
            s
        );
    }

    function cancelAuthorization(
        address authorizer,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external override whenNotPaused {
        _cancelAuthorization(authorizer, nonce, v, r, s);
    }
}