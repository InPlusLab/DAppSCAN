// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import { Create2 } from '@openzeppelin/contracts/utils/Create2.sol';

import { GoodAddressDeployer } from '../../libraries/GoodAddressDeployer.sol';

import { VToken, IVToken } from './VToken.sol';

abstract contract VTokenDeployer {
    struct DeployVTokenParams {
        string vTokenName;
        string vTokenSymbol;
        uint8 cTokenDecimals;
    }

    /// @notice Deploys contract VToken at an address such that the last 4 bytes of contract address is unique
    /// @dev Use of CREATE2 is not to recompute address in future, but just to have unique last 4 bytes
    /// @param params: parameters used for construction, see above struct
    /// @return vToken : the deployed VToken contract
    function _deployVToken(DeployVTokenParams calldata params) internal returns (IVToken vToken) {
        bytes memory bytecode = abi.encodePacked(
            type(VToken).creationCode,
            abi.encode(params.vTokenName, params.vTokenSymbol, params.cTokenDecimals)
        );

        vToken = IVToken(GoodAddressDeployer.deploy(0, bytecode, _isIVTokenAddressGood));
    }

    /// @notice Checks if it is fine to deploy vToken at the provided address
    /// @dev This method is implemented in RageTradeFactory
    /// @param addr potential address of vToken
    /// @return true if last 4 bytes are non-zero,
    function _isIVTokenAddressGood(address addr) internal view virtual returns (bool);
}
