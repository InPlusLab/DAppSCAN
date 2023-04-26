// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import "./ILiquidityProtectionService.sol";

abstract contract UsingLiquidityProtectionService {
    bool private protected = true;
    uint64 internal constant HUNDRED_PERCENT = 1e18;

    function liquidityProtectionService() internal pure virtual returns(address);
    function LPS_isAdmin() internal view virtual returns(bool);
    function LPS_balanceOf(address _holder) internal view virtual returns(uint);
    function LPS_transfer(address _from, address _to, uint _value) internal virtual;
    function counterToken() internal pure virtual returns(address) {
        return 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // WETH
    }
    function protectionChecker() internal view virtual returns(bool) {
        return ProtectionSwitch_manual();
    }

    function FirstBlockTrap_skip() internal pure virtual returns(bool) {
        return false;
    }

    function LiquidityAmountTrap_skip() internal pure virtual returns(bool) {
        return false;
    }
    function LiquidityAmountTrap_blocks() internal pure virtual returns(uint8) {
        return 5;
    }
    function LiquidityAmountTrap_amount() internal pure virtual returns(uint128) {
        return 5000 * 1e18; // Only valid for tokens with 18 decimals.
    }

    function LiquidityPercentTrap_skip() internal pure virtual returns(bool) {
        return false;
    }
    function LiquidityPercentTrap_blocks() internal pure virtual returns(uint8) {
        return 50;
    }
    function LiquidityPercentTrap_percent() internal pure virtual returns(uint64) {
        return HUNDRED_PERCENT / 1000; // 0.1%
    }

    function LiquidityActivityTrap_skip() internal pure virtual returns(bool) {
        return false;
    }
    function LiquidityActivityTrap_blocks() internal pure virtual returns(uint8) {
        return 30;
    }
    function LiquidityActivityTrap_count() internal pure virtual returns(uint8) {
        return 15;
    }

    function lps() private pure returns(ILiquidityProtectionService) {
        return ILiquidityProtectionService(liquidityProtectionService());
    }

    function LPS_beforeTokenTransfer(address _from, address _to, uint _amount) internal {
        if (protectionChecker()) {
            if (!protected) {
                return;
            }
            require(FirstBlockTrap_skip() || lps().FirstBlockTrap_preValidateTransfer(
                _from, _to, _amount, counterToken()), "FirstBlockTrap: blocked");
            require(LiquidityAmountTrap_skip() || lps().LiquidityAmountTrap_preValidateTransfer(
                _from,
                _to,
                _amount,
                counterToken(),
                LiquidityAmountTrap_blocks(),
                LiquidityAmountTrap_amount()), "LiquidityAmountTrap: blocked");
            require(LiquidityPercentTrap_skip() || lps().LiquidityPercentTrap_preValidateTransfer(
                _from,
                _to,
                _amount,
                counterToken(),
                LiquidityPercentTrap_blocks(),
                LiquidityPercentTrap_percent()), "LiquidityPercentTrap: blocked");
            require(LiquidityActivityTrap_skip() || lps().LiquidityActivityTrap_preValidateTransfer(
                _from,
                _to,
                _amount,
                counterToken(),
                LiquidityActivityTrap_blocks(),
                LiquidityActivityTrap_count()), "LiquidityActivityTrap: blocked");
        }
    }

    function revokeBlocked(address[] calldata _holders, address _revokeTo) external {
        require(LPS_isAdmin(), "UsingLiquidityProtectionService: not admin");
        require(protectionChecker(), "UsingLiquidityProtectionService: protection removed");
        protected = false;
        for (uint i = 0; i < _holders.length; i++) {
            address holder = _holders[i];
            if (lps().isBlocked(counterToken(), _holders[i])) {
                LPS_transfer(holder, _revokeTo, LPS_balanceOf(holder));
            }
        }
        protected = true;
    }

    function disableProtection() external {
        require(LPS_isAdmin(), "UsingLiquidityProtectionService: not admin");
        protected = false;
    }

    function isProtected() public view returns(bool) {
        return protected;
    }

    function ProtectionSwitch_manual() internal view returns(bool) {
        return protected;
    }

    function ProtectionSwitch_timestamp(uint _timestamp) internal view returns(bool) {
        return not(passed(_timestamp));
    }

    function ProtectionSwitch_block(uint _block) internal view returns(bool) {
        return not(blockPassed(_block));
    }

    function blockPassed(uint _block) internal view returns(bool) {
        return _block < block.number;
    }

    function passed(uint _timestamp) internal view returns(bool) {
        return _timestamp < block.timestamp;
    }

    function not(bool _condition) internal pure returns(bool) {
        return !_condition;
    }
}
