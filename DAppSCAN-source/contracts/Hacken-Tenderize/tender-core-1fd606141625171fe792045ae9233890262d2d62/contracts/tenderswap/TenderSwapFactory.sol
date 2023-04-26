// SPDX-FileCopyrightText: 2021 Tenderize <info@tenderize.me>

// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "./ITenderSwap.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

interface ITenderSwapFactory {
    struct Config {
        IERC20 token0;
        IERC20 token1;
        string lpTokenName;
        string lpTokenSymbol; // e.g. tLPT-LPT-SWAP
    }

    function deploy(Config calldata _config) external returns (ITenderSwap);
}

contract TenderSwapFactoryV1 is ITenderSwapFactory {
    event NewTenderSwap(
        ITenderSwap tenderSwap,
        string lpTokenName,
        string lpTokenSymbol,
        uint256 amplifier,
        uint256 fee,
        uint256 adminFee
    );

    ITenderSwap immutable tenderSwapTarget;
    LiquidityPoolToken immutable lpTokenTarget;
    uint256 immutable amplifier;
    uint256 immutable fee;
    uint256 immutable adminFee;

    constructor(
        ITenderSwap _tenderSwapTarget,
        LiquidityPoolToken _lpTokenTarget,
        uint256 _amplifier,
        uint256 _fee,
        uint256 _adminFee
    ) {
        tenderSwapTarget = _tenderSwapTarget;
        lpTokenTarget = _lpTokenTarget;
        amplifier = _amplifier;
        fee = _fee;
        adminFee = _adminFee;
    }

    function deploy(Config calldata _config) external override(ITenderSwapFactory) returns (ITenderSwap tenderSwap) {
        tenderSwap = ITenderSwap(Clones.clone(address(tenderSwapTarget)));

        require(
            tenderSwap.initialize(
                _config.token0,
                _config.token1,
                _config.lpTokenName,
                _config.lpTokenSymbol,
                amplifier,
                fee,
                adminFee,
                lpTokenTarget
            ),
            "FAIL_INIT_TENDERSWAP"
        );

        tenderSwap.transferOwnership(msg.sender);

        emit NewTenderSwap(tenderSwap, _config.lpTokenName, _config.lpTokenSymbol, amplifier, fee, adminFee);
    }
}
