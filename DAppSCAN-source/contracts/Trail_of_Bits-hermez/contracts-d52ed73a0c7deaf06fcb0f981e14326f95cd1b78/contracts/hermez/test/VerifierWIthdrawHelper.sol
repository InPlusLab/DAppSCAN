// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.6.12;

import "../interfaces/VerifierWithdrawInterface.sol";

contract VerifierWithdrawHelper is VerifierWithdrawInterface {
    function verifyProof(
        uint256[2] calldata a,
        uint256[2][2] calldata b,
        uint256[2] calldata c,
        uint256[1] calldata input
    ) public override view returns (bool) {
        return true;
    }
}
