// SPDX-License-Identifier: AGPL-3.0-only

/*
    SkaleDkgPreResponse.sol - SKALE Manager
    Copyright (C) 2021-Present SKALE Labs
    @author Dmytro Stebaiev
    @author Artem Payvin
    @author Vadim Yavorsky

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

import "@skalenetwork/skale-manager-interfaces/ISkaleDKG.sol";
import "@skalenetwork/skale-manager-interfaces/IContractManager.sol";

import "../utils/FieldOperations.sol";

/**
 * @title SkaleDkgPreResponse
 * @dev Contains functions to manage distributed key generation per
 * Joint-Feldman protocol.
 */
library SkaleDkgPreResponse {
    using G2Operations for ISkaleDKG.G2Point;

    function preResponse(
        bytes32 schainHash,
        uint fromNodeIndex,
        ISkaleDKG.G2Point[] memory verificationVector,
        ISkaleDKG.G2Point[] memory verificationVectorMultiplication,
        ISkaleDKG.KeyShare[] memory secretKeyContribution,
        IContractManager contractManager,
        mapping(bytes32 => ISkaleDKG.ComplaintData) storage complaints,
        mapping(bytes32 => mapping(uint => bytes32)) storage hashedData
    )
        external
    {
        ISkaleDKG skaleDKG = ISkaleDKG(contractManager.getContract("SkaleDKG"));
        uint index = _preResponseCheck(
            schainHash,
            fromNodeIndex,
            verificationVector,
            verificationVectorMultiplication,
            secretKeyContribution,
            skaleDKG,
            complaints,
            hashedData
        );
        _processPreResponse(
            secretKeyContribution[index].share,
            schainHash,
            verificationVectorMultiplication,
            complaints
        );
    }

    function _processPreResponse(
        bytes32 share,
        bytes32 schainHash,
        ISkaleDKG.G2Point[] memory verificationVectorMultiplication,
        mapping(bytes32 => ISkaleDKG.ComplaintData) storage complaints
    )
        private
    {
        complaints[schainHash].keyShare = share;
        complaints[schainHash].sumOfVerVec = _calculateSum(verificationVectorMultiplication);
        complaints[schainHash].isResponse = true;
    }

    function _preResponseCheck(
        bytes32 schainHash,
        uint fromNodeIndex,
        ISkaleDKG.G2Point[] memory verificationVector,
        ISkaleDKG.G2Point[] memory verificationVectorMultiplication,
        ISkaleDKG.KeyShare[] memory secretKeyContribution,
        ISkaleDKG skaleDKG,
        mapping(bytes32 => ISkaleDKG.ComplaintData) storage complaints,
        mapping(bytes32 => mapping(uint => bytes32)) storage hashedData
    )
        private
        view
        returns (uint index)
    {
        (uint indexOnSchain, ) = skaleDKG.checkAndReturnIndexInGroup(schainHash, fromNodeIndex, true);
        require(complaints[schainHash].nodeToComplaint == fromNodeIndex, "Not this Node");
        require(!complaints[schainHash].isResponse, "Already submitted pre response data");
        require(
            hashedData[schainHash][indexOnSchain] == skaleDKG.hashData(secretKeyContribution, verificationVector),
            "Broadcasted Data is not correct"
        );
        require(
            verificationVector.length == verificationVectorMultiplication.length,
            "Incorrect length of multiplied verification vector"
        );
        (index, ) = skaleDKG.checkAndReturnIndexInGroup(schainHash, complaints[schainHash].fromNodeToComplaint, true);
        require(
            _checkCorrectVectorMultiplication(index, verificationVector, verificationVectorMultiplication),
            "Multiplied verification vector is incorrect"
        ); 
    }

    function _calculateSum(ISkaleDKG.G2Point[] memory verificationVectorMultiplication)
        private
        view
        returns (ISkaleDKG.G2Point memory)
    {
        ISkaleDKG.G2Point memory value = G2Operations.getG2Zero();
        for (uint i = 0; i < verificationVectorMultiplication.length; i++) {
            value = value.addG2(verificationVectorMultiplication[i]);
        }
        return value;
    }

    function _checkCorrectVectorMultiplication(
        uint indexOnSchain,
        ISkaleDKG.G2Point[] memory verificationVector,
        ISkaleDKG.G2Point[] memory verificationVectorMultiplication
    )
        private
        view
        returns (bool)
    {
        ISkaleDKG.Fp2Point memory value = G1Operations.getG1Generator();
        ISkaleDKG.Fp2Point memory tmp = G1Operations.getG1Generator();
        for (uint i = 0; i < verificationVector.length; i++) {
            (tmp.a, tmp.b) = Precompiled.bn256ScalarMul(value.a, value.b, (indexOnSchain + 1) ** i);
            if (!_checkPairing(tmp, verificationVector[i], verificationVectorMultiplication[i])) {
                return false;
            }
        }
        return true;
    }

    function _checkPairing(
        ISkaleDKG.Fp2Point memory g1Mul,
        ISkaleDKG.G2Point memory verificationVector,
        ISkaleDKG.G2Point memory verificationVectorMultiplication
    )
        private
        view
        returns (bool)
    {
        require(G1Operations.checkRange(g1Mul), "g1Mul is not valid");
        g1Mul.b = G1Operations.negate(g1Mul.b);
        ISkaleDKG.Fp2Point memory one = G1Operations.getG1Generator();
        return Precompiled.bn256Pairing(
            one.a, one.b,
            verificationVectorMultiplication.x.b, verificationVectorMultiplication.x.a,
            verificationVectorMultiplication.y.b, verificationVectorMultiplication.y.a,
            g1Mul.a, g1Mul.b,
            verificationVector.x.b, verificationVector.x.a,
            verificationVector.y.b, verificationVector.y.a
        );
    }

}