// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2015, 2016, 2017 Dapphub
// Adapted by Ethereum Community 2021
pragma solidity 0.8.13;

// TODO(Astrid): Fix this to use public IERC20. (need to implement increase/decreaseAllowance).
import "./IERC20.sol";
import "./IERC2612.sol";
import "./IERC3156FlashLender.sol";

/// @dev Wrapped Astar (WASTR) is an Astar (ASTR) ERC-20 wrapper. You can `deposit` ASTR and obtain a WASTR balance which can then be operated as an ERC-20 token. You can
/// `withdraw` ASTR from WASTR, which will then burn WASTR token in your wallet. The amount of WASTR token in any wallet is always identical to the
/// balance of ASTR deposited minus the ASTR withdrawn with that specific wallet.
interface IWASTR is IERC20, IERC2612, IERC3156FlashLender {

    /// @dev Returns current amount of flash-minted WASTR token.
    function flashMinted() external view returns(uint256);

    /// @dev `msg.value` of ASTR sent to this contract grants caller account a matching increase in WASTR token balance.
    /// Emits {Transfer} event to reflect WASTR token mint of `msg.value` from `address(0)` to caller account.
    function deposit() external payable;

    /// @dev `msg.value` of ASTR sent to this contract grants `to` account a matching increase in WASTR token balance.
    /// Emits {Transfer} event to reflect WASTR token mint of `msg.value` from `address(0)` to `to` account.
    function depositTo(address to) external payable;

    /// @dev Burn `value` WASTR token from caller account and withdraw matching ASTR to the same.
    /// Emits {Transfer} event to reflect WASTR token burn of `value` to `address(0)` from caller account. 
    /// Requirements:
    ///   - caller account must have at least `value` balance of WASTR token.
    function withdraw(uint256 value) external;

    /// @dev Burn `value` WASTR token from caller account and withdraw matching ASTR to account (`to`).
    /// Emits {Transfer} event to reflect WASTR token burn of `value` to `address(0)` from caller account.
    /// Requirements:
    ///   - caller account must have at least `value` balance of WASTR token.
    function withdrawTo(address payable to, uint256 value) external;

    /// @dev Burn `value` WASTR token from account (`from`) and withdraw matching ASTR to account (`to`).
    /// Emits {Approval} event to reflect reduced allowance `value` for caller account to spend from account (`from`),
    /// unless allowance is set to `type(uint256).max`
    /// Emits {Transfer} event to reflect WASTR token burn of `value` to `address(0)` from account (`from`).
    /// Requirements:
    ///   - `from` account must have at least `value` balance of WASTR token.
    ///   - `from` account must have approved caller to spend at least `value` of WASTR token, unless `from` and caller are the same account.
    function withdrawFrom(address from, address payable to, uint256 value) external;

    /// @dev `msg.value` of ASTR sent to this contract grants `to` account a matching increase in WASTR token balance,
    /// after which a call is executed to an ERC677-compliant contract with the `data` parameter.
    /// Emits {Transfer} event.
    /// Returns boolean value indicating whether operation succeeded.
    /// For more information on {transferAndCall} format, see https://github.com/ethereum/EIPs/issues/677.
    function depositToAndCall(address to, bytes calldata data) external payable returns (bool);

    /// @dev Sets `value` as allowance of `spender` account over caller account's WASTR token,
    /// after which a call is executed to an ERC677-compliant contract with the `data` parameter.
    /// Emits {Approval} event.
    /// Returns boolean value indicating whether operation succeeded.
    /// For more information on {approveAndCall} format, see https://github.com/ethereum/EIPs/issues/677.
    function approveAndCall(address spender, uint256 value, bytes calldata data) external returns (bool);

    /// @dev Moves `value` WASTR token from caller's account to account (`to`), 
    /// after which a call is executed to an ERC677-compliant contract with the `data` parameter.
    /// A transfer to `address(0)` triggers an ASTR withdraw matching the sent WASTR token in favor of caller.
    /// Emits {Transfer} event.
    /// Returns boolean value indicating whether operation succeeded.
    /// Requirements:
    ///   - caller account must have at least `value` WASTR token.
    /// For more information on {transferAndCall} format, see https://github.com/ethereum/EIPs/issues/677.
    function transferAndCall(address to, uint value, bytes calldata data) external returns (bool);
}