/*
    SkaleVerifier.sol - SKALE Manager
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

pragma solidity 0.5.16;

import "./Permissions.sol";
import "./interfaces/IGroupsData.sol";


contract SkaleVerifier is Permissions {


    uint constant P = 21888242871839275222246405745257275088696311157297823662689037894645226208583;

    uint constant G2A = 10857046999023057135944570762232829481370756359578518086990519993285655852781;
    uint constant G2B = 11559732032986387107991004021392285783925812861821192530917403151452391805634;
    uint constant G2C = 8495653923123431417604973247489272438418190587263600148770280649306958101930;
    uint constant G2D = 4082367875863433681332203403145435568316851327593401208105741076214120093531;

    uint constant TWISTBX = 19485874751759354771024239261021720505790618469301721065564631296452457478373;
    uint constant TWISTBY = 266929791119991161246907387137283842545076965332900288569378510910307636690;

    struct Fp2 {
        uint x;
        uint y;
    }

    function verifySchainSignature(
        uint signA,
        uint signB,
        bytes32 hash,
        uint counter,
        uint hashA,
        uint hashB,
        string calldata schainName
    )
        external
        view
        returns (bool)
    {
        if (!checkHashToGroupWithHelper(
            hash,
            counter,
            hashA,
            hashB
            )
        )
        {
            return false;
        }

        address schainsDataAddress = contractManager.getContract("SchainsData");
        (uint pkA, uint pkB, uint pkC, uint pkD) = IGroupsData(schainsDataAddress).getGroupsPublicKey(
            keccak256(abi.encodePacked(schainName))
        );
        return verify(
            signA,
            signB,
            hash,
            counter,
            hashA,
            hashB,
            pkA,
            pkB,
            pkC,
            pkD
        );
    }

    function initialize(address newContractsAddress) public initializer {
        Permissions.initialize(newContractsAddress);
    }

    function verify(
        uint signA,
        uint signB,
        bytes32 hash,
        uint counter,
        uint hashA,
        uint hashB,
        uint pkA,
        uint pkB,
        uint pkC,
        uint pkD) public view returns (bool)
    {
        if (!checkHashToGroupWithHelper(
            hash,
            counter,
            hashA,
            hashB
            )
        )
        {
            return false;
        }

        uint newSignB;
        if (!(signA == 0 && signB == 0)) {
            newSignB = P.sub((signB % P));
        } else {
            newSignB = signB;
        }

        require(isG1(signA, newSignB), "Sign not in G1");
        require(isG1(hashA, hashB), "Hash not in G1");

        require(isG2(Fp2({x: G2A, y: G2B}), Fp2({x: G2C, y: G2D})), "G2.one not in G2");
        require(isG2(Fp2({x: pkA, y: pkB}), Fp2({x: pkC, y: pkD})), "Public Key not in G2");

        bool success;
        uint[12] memory inputToPairing;
        inputToPairing[0] = signA;
        inputToPairing[1] = newSignB;
        inputToPairing[2] = G2B;
        inputToPairing[3] = G2A;
        inputToPairing[4] = G2D;
        inputToPairing[5] = G2C;
        inputToPairing[6] = hashA;
        inputToPairing[7] = hashB;
        inputToPairing[8] = pkB;
        inputToPairing[9] = pkA;
        inputToPairing[10] = pkD;
        inputToPairing[11] = pkC;
        uint[1] memory out;
        assembly {
            success := staticcall(not(0), 8, inputToPairing, mul(12, 0x20), out, 0x20)
        }
        require(success, "Pairing check failed");
        return out[0] != 0;
    }

    function checkHashToGroupWithHelper(
        bytes32 hash,
        uint counter,
        uint hashA,
        uint hashB
    )
        internal
        pure
        returns (bool)
    {
        uint xCoord = uint(hash) % P;
        xCoord = (xCoord.add(counter)) % P;

        uint ySquared = addmod(mulmod(mulmod(xCoord, xCoord, P), xCoord, P), 3, P);
        if (hashB < P / 2 || mulmod(hashB, hashB, P) != ySquared || xCoord != hashA) {
            return false;
        }

        return true;
    }

    // Fp2 operations

    function addFp2(Fp2 memory a, Fp2 memory b) internal pure returns (Fp2 memory) {
        return Fp2({ x: addmod(a.x, b.x, P), y: addmod(a.y, b.y, P) });
    }

    function scalarMulFp2(uint scalar, Fp2 memory a) internal pure returns (Fp2 memory) {
        return Fp2({ x: mulmod(scalar, a.x, P), y: mulmod(scalar, a.y, P) });
    }

    function minusFp2(Fp2 memory a, Fp2 memory b) internal pure returns (Fp2 memory) {
        uint first;
        uint second;
        if (a.x >= b.x) {
            first = addmod(a.x, P.sub(b.x), P);
        } else {
            first = P.sub(addmod(b.x, P.sub(a.x), P));
        }
        if (a.y >= b.y) {
            second = addmod(a.y, P.sub(b.y), P);
        } else {
            second = P.sub(addmod(b.y, P.sub(a.y), P));
        }
        return Fp2({ x: first, y: second });
    }

    function mulFp2(Fp2 memory a, Fp2 memory b) internal pure returns (Fp2 memory) {
        uint aA = mulmod(a.x, b.x, P);
        uint bB = mulmod(a.y, b.y, P);
        return Fp2({
            x: addmod(aA, mulmod(P - 1, bB, P), P),
            y: addmod(mulmod(addmod(a.x, a.y, P), addmod(b.x, b.y, P), P), P.sub(addmod(aA, bB, P)), P)
        });
    }

    function squaredFp2(Fp2 memory a) internal pure returns (Fp2 memory) {
        uint ab = mulmod(a.x, a.y, P);
        uint mult = mulmod(addmod(a.x, a.y, P), addmod(a.x, mulmod(P - 1, a.y, P), P), P);
        return Fp2({ x: mult, y: addmod(ab, ab, P) });
    }

    function inverseFp2(Fp2 memory a) internal view returns (Fp2 memory x) {
        uint t0 = mulmod(a.x, a.x, P);
        uint t1 = mulmod(a.y, a.y, P);
        uint t2 = mulmod(P - 1, t1, P);
        if (t0 >= t2) {
            t2 = addmod(t0, P.sub(t2), P);
        } else {
            t2 = P.sub(addmod(t2, P.sub(t0), P));
        }
        uint t3 = bigModExp(t2, P - 2);
        x.x = mulmod(a.x, t3, P);
        x.y = P.sub(mulmod(a.y, t3, P));
    }

    // End of Fp2 operations

    function isG1(uint x, uint y) internal pure returns (bool) {
        return mulmod(y, y, P) == addmod(mulmod(mulmod(x, x, P), x, P), 3, P);
    }

    function isG2(Fp2 memory x, Fp2 memory y) internal pure returns (bool) {
        if (isG2Zero(x, y)) {
            return true;
        }
        Fp2 memory squaredY = squaredFp2(y);
        Fp2 memory res = minusFp2(minusFp2(squaredY, mulFp2(squaredFp2(x), x)), Fp2({x: TWISTBX, y: TWISTBY}));
        return res.x == 0 && res.y == 0;
    }

    function isG2Zero(Fp2 memory x, Fp2 memory y) internal pure returns (bool) {
        return x.x == 0 && x.y == 0 && y.x == 1 && y.y == 0;
    }

    function bigModExp(uint base, uint power) internal view returns (uint) {
        uint[6] memory inputToBigModExp;
        inputToBigModExp[0] = 32;
        inputToBigModExp[1] = 32;
        inputToBigModExp[2] = 32;
        inputToBigModExp[3] = base;
        inputToBigModExp[4] = power;
        inputToBigModExp[5] = P;
        uint[1] memory out;
        bool success;
        assembly {
            success := staticcall(not(0), 5, inputToBigModExp, mul(6, 0x20), out, 0x20)
        }
        require(success, "BigModExp failed");
        return out[0];
    }
}
