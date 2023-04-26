/*
    SkaleDKG.sol - SKALE Manager
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

pragma solidity ^0.5.3;
pragma experimental ABIEncoderV2;
import "./Permissions.sol";
import "./interfaces/IGroupsData.sol";
import "./interfaces/INodesData.sol";
import "./interfaces/ISchainsFunctionality.sol";
import "./interfaces/ISchainsFunctionalityInternal.sol";
import "./delegation/DelegationService.sol";
import "./NodesData.sol";
import "./SlashingTable.sol";


interface IECDH {
    function deriveKey(
        uint256 privKey,
        uint256 pubX,
        uint256 pubY
    )
        external
        pure
        returns (uint256, uint256);
}

interface IDecryption {
    function decrypt(bytes32 ciphertext, bytes32 key) external pure returns (uint256);
}


contract SkaleDKG is Permissions {

    struct Channel {
        bool active;
        address dataAddress;
        bool[] broadcasted;
        uint numberOfBroadcasted;
        Fp2 publicKeyx;
        Fp2 publicKeyy;
        uint numberOfCompleted;
        bool[] completed;
        uint startedBlockNumber;
        uint nodeToComplaint;
        uint fromNodeToComplaint;
        uint startComplaintBlockNumber;
    }

    struct Fp2 {
        uint x;
        uint y;
    }

    struct BroadcastedData {
        bytes secretKeyContribution;
        bytes verificationVector;
    }

    uint constant P = 21888242871839275222246405745257275088696311157297823662689037894645226208583;

    uint constant G2A = 10857046999023057135944570762232829481370756359578518086990519993285655852781;
    uint constant G2B = 11559732032986387107991004021392285783925812861821192530917403151452391805634;
    uint constant G2C = 8495653923123431417604973247489272438418190587263600148770280649306958101930;
    uint constant G2D = 4082367875863433681332203403145435568316851327593401208105741076214120093531;

    uint constant TWISTBX = 19485874751759354771024239261021720505790618469301721065564631296452457478373;
    uint constant TWISTBY = 266929791119991161246907387137283842545076965332900288569378510910307636690;

    uint constant G1A = 1;
    uint constant G1B = 2;

    mapping(bytes32 => Channel) public channels;
    mapping(bytes32 => mapping(uint => BroadcastedData)) data;

    event ChannelOpened(bytes32 groupIndex);

    event ChannelClosed(bytes32 groupIndex);

    event BroadcastAndKeyShare(
        bytes32 indexed groupIndex,
        uint indexed fromNode,
        bytes verificationVector,
        bytes secretKeyContribution
    );

    event AllDataReceived(bytes32 indexed groupIndex, uint nodeIndex);
    event SuccessfulDKG(bytes32 indexed groupIndex);
    event BadGuy(uint nodeIndex);
    event FailedDKG(bytes32 indexed groupIndex);
    event ComplaintSent(bytes32 indexed groupIndex, uint indexed fromNodeIndex, uint indexed toNodeIndex);
    event NewGuy(uint nodeIndex);

    modifier correctGroup(bytes32 groupIndex) {
        require(channels[groupIndex].active, "Group is not created");
        _;
    }

    modifier correctNode(bytes32 groupIndex, uint nodeIndex) {
        uint index = findNode(groupIndex, nodeIndex);
        require(index < IGroupsData(channels[groupIndex].dataAddress).getNumberOfNodesInGroup(groupIndex), "Node is not in this group");
        _;
    }

    constructor(address contractsAddress) Permissions(contractsAddress) public {

    }

    function openChannel(bytes32 groupIndex) external allowThree("SchainsData", "MonitorsData", "SkaleDKG") {
        require(!channels[groupIndex].active, "Channel already is created");
        channels[groupIndex].active = true;
        channels[groupIndex].dataAddress = msg.sender;
        channels[groupIndex].broadcasted = new bool[](IGroupsData(channels[groupIndex].dataAddress).getRecommendedNumberOfNodes(groupIndex));
        channels[groupIndex].completed = new bool[](IGroupsData(channels[groupIndex].dataAddress).getRecommendedNumberOfNodes(groupIndex));
        channels[groupIndex].publicKeyy.x = 1;
        channels[groupIndex].nodeToComplaint = uint(-1);
        emit ChannelOpened(groupIndex);
    }

    function deleteChannel(bytes32 groupIndex) external allowTwo("SchainsData", "MonitorsData") {
        require(channels[groupIndex].active, "Channel is not created");
        delete channels[groupIndex];
    }

    function broadcast(
        bytes32 groupIndex,
        uint nodeIndex,
        bytes calldata verificationVector,
        bytes calldata secretKeyContribution
    )
        external
        correctGroup(groupIndex)
        correctNode(groupIndex, nodeIndex)
    {
        require(isNodeByMessageSender(nodeIndex, msg.sender), "Node does not exist for message sender");
        isBroadcast(
            groupIndex,
            nodeIndex,
            secretKeyContribution,
            verificationVector
        );
        bytes32 vector;
        bytes32 vector1;
        bytes32 vector2;
        bytes32 vector3;
        assembly {
            vector := calldataload(add(4, 160))
            vector1 := calldataload(add(4, 192))
            vector2 := calldataload(add(4, 224))
            vector3 := calldataload(add(4, 256))
        }
        adding(
            groupIndex,
            uint(vector),
            uint(vector1),
            uint(vector2),
            uint(vector3)
        );
        emit BroadcastAndKeyShare(
            groupIndex,
            nodeIndex,
            verificationVector,
            secretKeyContribution
        );
    }

    function complaint(bytes32 groupIndex, uint fromNodeIndex, uint toNodeIndex)
        external
        correctGroup(groupIndex)
        correctNode(groupIndex, fromNodeIndex)
        correctNode(groupIndex, toNodeIndex)
    {
        require(isNodeByMessageSender(fromNodeIndex, msg.sender), "Node does not exist for message sender");
        if (isBroadcasted(groupIndex, toNodeIndex) && channels[groupIndex].nodeToComplaint == uint(-1)) {
            // need to wait a response from toNodeIndex
            channels[groupIndex].nodeToComplaint = toNodeIndex;
            channels[groupIndex].fromNodeToComplaint = fromNodeIndex;
            channels[groupIndex].startComplaintBlockNumber = block.number;
            emit ComplaintSent(groupIndex, fromNodeIndex, toNodeIndex);
        } else if (isBroadcasted(groupIndex, toNodeIndex) && channels[groupIndex].nodeToComplaint != toNodeIndex) {
            revert("One complaint has already sent");
        } else if (isBroadcasted(groupIndex, toNodeIndex) && channels[groupIndex].nodeToComplaint == toNodeIndex) {
            require(channels[groupIndex].startComplaintBlockNumber + 120 <= block.number, "One more complaint rejected");
            // need to penalty Node - toNodeIndex
            finalizeSlashing(groupIndex, channels[groupIndex].nodeToComplaint);
        } else if (!isBroadcasted(groupIndex, toNodeIndex)) {
            // if node have not broadcasted params
            require(channels[groupIndex].startedBlockNumber + 120 <= block.number, "Complaint rejected");
            // need to penalty Node - toNodeIndex
            finalizeSlashing(groupIndex, channels[groupIndex].nodeToComplaint);
        }
    }

    function response(
        bytes32 groupIndex,
        uint fromNodeIndex,
        uint secretNumber,
        bytes calldata multipliedShare
    )
        external
        correctGroup(groupIndex)
        correctNode(groupIndex, fromNodeIndex)
    {
        require(channels[groupIndex].nodeToComplaint == fromNodeIndex, "Not this Node");
        require(isNodeByMessageSender(fromNodeIndex, msg.sender), "Node does not exist for message sender");

        // uint secret = decryptMessage(groupIndex, secretNumber);

        // DKG verification(secret key contribution, verification vector)
        // uint indexOfNode = findNode(groupIndex, fromNodeIndex);
        // bytes memory verVec = data[groupIndex][indexOfNode].verificationVector;
        bool verificationResult = verify(
            groupIndex,
            fromNodeIndex,
            secretNumber,
            multipliedShare
        );
        uint badNode = (verificationResult ? channels[groupIndex].fromNodeToComplaint : channels[groupIndex].nodeToComplaint);
        finalizeSlashing(groupIndex, badNode);
    }

    function alright(bytes32 groupIndex, uint fromNodeIndex)
        external
        correctGroup(groupIndex)
        correctNode(groupIndex, fromNodeIndex)
    {
        require(isNodeByMessageSender(fromNodeIndex, msg.sender), "Node does not exist for message sender");
        uint index = findNode(groupIndex, fromNodeIndex);
        uint numberOfParticipant = IGroupsData(channels[groupIndex].dataAddress).getNumberOfNodesInGroup(groupIndex);
        require(numberOfParticipant == channels[groupIndex].numberOfBroadcasted, "Still Broadcasting phase");
        require(!channels[groupIndex].completed[index], "Node is already alright");
        channels[groupIndex].completed[index] = true;
        channels[groupIndex].numberOfCompleted++;
        emit AllDataReceived(groupIndex, fromNodeIndex);
        if (channels[groupIndex].numberOfCompleted == numberOfParticipant) {
            IGroupsData(channels[groupIndex].dataAddress).setPublicKey(
                groupIndex,
                channels[groupIndex].publicKeyx.x,
                channels[groupIndex].publicKeyx.y,
                channels[groupIndex].publicKeyy.x,
                channels[groupIndex].publicKeyy.y
            );
            delete channels[groupIndex];
            emit SuccessfulDKG(groupIndex);
        }
    }

    function isChannelOpened(bytes32 groupIndex) external view returns (bool) {
        return channels[groupIndex].active;
    }

    function isBroadcastPossible(bytes32 groupIndex, uint nodeIndex) external view returns (bool) {
        uint index = findNode(groupIndex, nodeIndex);
        return channels[groupIndex].active &&
            index < IGroupsData(channels[groupIndex].dataAddress).getNumberOfNodesInGroup(groupIndex) &&
            isNodeByMessageSender(nodeIndex, msg.sender) &&
            !channels[groupIndex].broadcasted[index];
    }

    function isComplaintPossible(bytes32 groupIndex, uint fromNodeIndex, uint toNodeIndex) external view returns (bool) {
        uint indexFrom = findNode(groupIndex, fromNodeIndex);
        uint indexTo = findNode(groupIndex, toNodeIndex);
        bool complaintSending = channels[groupIndex].nodeToComplaint == uint(-1) ||
            (
                channels[groupIndex].broadcasted[indexTo] &&
                channels[groupIndex].startComplaintBlockNumber + 120 <= block.number &&
                channels[groupIndex].nodeToComplaint == toNodeIndex
            ) ||
            (
                !channels[groupIndex].broadcasted[indexTo] &&
                channels[groupIndex].nodeToComplaint == toNodeIndex &&
                channels[groupIndex].startedBlockNumber + 120 <= block.number
            );
        return channels[groupIndex].active &&
            indexFrom < IGroupsData(channels[groupIndex].dataAddress).getNumberOfNodesInGroup(groupIndex) &&
            indexTo < IGroupsData(channels[groupIndex].dataAddress).getNumberOfNodesInGroup(groupIndex) &&
            isNodeByMessageSender(fromNodeIndex, msg.sender) &&
            complaintSending;
    }

    function isAlrightPossible(bytes32 groupIndex, uint nodeIndex) external view returns (bool) {
        uint index = findNode(groupIndex, nodeIndex);
        return channels[groupIndex].active &&
            index < IGroupsData(channels[groupIndex].dataAddress).getNumberOfNodesInGroup(groupIndex) &&
            isNodeByMessageSender(nodeIndex, msg.sender) &&
            IGroupsData(channels[groupIndex].dataAddress).getNumberOfNodesInGroup(groupIndex) == channels[groupIndex].numberOfBroadcasted &&
            !channels[groupIndex].completed[index];
    }

    function isResponsePossible(bytes32 groupIndex, uint nodeIndex) external view returns (bool) {
        uint index = findNode(groupIndex, nodeIndex);
        return channels[groupIndex].active &&
            index < IGroupsData(channels[groupIndex].dataAddress).getNumberOfNodesInGroup(groupIndex) &&
            isNodeByMessageSender(nodeIndex, msg.sender) &&
            channels[groupIndex].nodeToComplaint == nodeIndex;
    }

    function finalizeSlashing(bytes32 groupIndex, uint badNode) internal {
        address schainsFunctionalityInternalAddress = contractManager.getContract("SchainsFunctionalityInternal");
        uint[] memory possibleNodes = ISchainsFunctionalityInternal(schainsFunctionalityInternalAddress).isEnoughNodes(groupIndex);
        emit BadGuy(badNode);
        emit FailedDKG(groupIndex);

        address dataAddress = channels[groupIndex].dataAddress;
        delete channels[groupIndex];
        if (possibleNodes.length > 0) {
            uint newNode = ISchainsFunctionalityInternal(schainsFunctionalityInternalAddress).replaceNode(
                badNode,
                groupIndex
            );
            emit NewGuy(newNode);
            this.openChannel(groupIndex);
        } else {
            ISchainsFunctionalityInternal(schainsFunctionalityInternalAddress).excludeNodeFromSchain(
                badNode,
                groupIndex
            );
            IGroupsData(dataAddress).setGroupFailedDKG(groupIndex);
        }

        DelegationService delegationService = DelegationService(contractManager.getContract("DelegationService"));
        NodesData nodesData = NodesData(contractManager.getContract("NodesData"));
        SlashingTable slashingTable = SlashingTable(contractManager.getContract("SlashingTable"));

        delegationService.slash(nodesData.getValidatorId(badNode), slashingTable.getPenalty("FailedDKG"));
    }

    function verify(
        bytes32 groupIndex,
        uint fromNodeIndex,
        uint secretNumber,
        bytes memory multipliedShare
    )
        internal
        view
        returns (bool)
    {
        uint index = findNode(groupIndex, fromNodeIndex);
        uint secret = decryptMessage(groupIndex, secretNumber);
        bytes memory verificationVector = data[groupIndex][index].verificationVector;
        Fp2 memory valX = Fp2({x: 0, y: 0});
        Fp2 memory valY = Fp2({x: 1, y: 0});
        Fp2 memory tmpX = Fp2({x: 0, y: 0});
        Fp2 memory tmpY = Fp2({x: 1, y: 0});
        for (uint i = 0; i < verificationVector.length / 128; i++) {
            (tmpX, tmpY) = loop(index, verificationVector, i);
            (valX, valY) = addG2(
                tmpX,
                tmpY,
                valX,
                valY
            );
        }
        return checkDKGVerification(valX, valY, multipliedShare) && checkCorrectMultipliedShare(multipliedShare, secret);
    }

    function getCommonPublicKey(bytes32 groupIndex, uint256 secretNumber) internal view returns (bytes32 key) {
        address nodesDataAddress = contractManager.getContract("NodesData");
        address ecdhAddress = contractManager.getContract("ECDH");
        bytes memory publicKey = INodesData(nodesDataAddress).getNodePublicKey(channels[groupIndex].fromNodeToComplaint);
        uint256 pkX;
        uint256 pkY;

        (pkX, pkY) = bytesToPublicKey(publicKey);

        (pkX, pkY) = IECDH(ecdhAddress).deriveKey(secretNumber, pkX, pkY);

        key = bytes32(pkX);
    }

    /*function hashed(uint x) public pure returns (bytes32) {
        return sha256(abi.encodePacked(uint2str(x)));
    }

    function toBytes(uint256 x) internal pure returns (bytes memory b) {
        b = new bytes(32);
        assembly { mstore(add(b, 32), x) }
    }

    function uint2str(uint num) internal pure returns (string memory) {
        if (num == 0) {
            return "0";
        }
        uint j = num;
        uint len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint k = len - 1;
        uint num2 = num;
        while (num2 != 0) {
            bstr[k--] = byte(uint8(48 + num2 % 10));
            num2 /= 10;
        }
        return string(bstr);
    }

    function bytes32ToString(bytes32 x) internal pure returns (string memory) {
        bytes memory bytesString = new bytes(32);
        uint charCount = 0;
        for (uint j = 0; j < 32; j++) {
            byte char = byte(bytes32(uint(x) * 2 ** (8 * j)));
            if (char != 0) {
                bytesString[charCount] = char;
                charCount++;
            }
        }
        bytes memory bytesStringTrimmed = new bytes(charCount);
        for (uint j = 0; j < charCount; j++) {
            bytesStringTrimmed[j] = bytesString[j];
        }
        return string(bytesStringTrimmed);
    }*/

    function decryptMessage(bytes32 groupIndex, uint secretNumber) internal view returns (uint) {
        address decryptionAddress = contractManager.getContract("Decryption");

        bytes32 key = getCommonPublicKey(groupIndex, secretNumber);

        // Decrypt secret key contribution
        bytes32 ciphertext;
        uint index = findNode(groupIndex, channels[groupIndex].fromNodeToComplaint);
        uint indexOfNode = findNode(groupIndex, channels[groupIndex].nodeToComplaint);
        bytes memory sc = data[groupIndex][indexOfNode].secretKeyContribution;
        assembly {
            ciphertext := mload(add(sc, add(32, mul(index, 97))))
        }

        uint secret = IDecryption(decryptionAddress).decrypt(ciphertext, key);
        return secret;
    }

    function adding(
        bytes32 groupIndex,
        uint x1,
        uint y1,
        uint x2,
        uint y2
    )
        internal
    {
        require(isG2(Fp2({ x: x1, y: y1 }), Fp2({ x: x2, y: y2 })), "Incorrect G2 point");
        (channels[groupIndex].publicKeyx, channels[groupIndex].publicKeyy) = addG2(
            Fp2({ x: x1, y: y1 }),
            Fp2({ x: x2, y: y2 }),
            channels[groupIndex].publicKeyx,
            channels[groupIndex].publicKeyy
        );
    }

    function isBroadcast(
        bytes32 groupIndex,
        uint nodeIndex,
        bytes memory sc,
        bytes memory vv
    )
        internal
    {
        uint index = findNode(groupIndex, nodeIndex);
        require(channels[groupIndex].broadcasted[index] == false, "This node is already broadcasted");
        channels[groupIndex].broadcasted[index] = true;
        channels[groupIndex].numberOfBroadcasted++;
        data[groupIndex][index] = BroadcastedData({
            secretKeyContribution: sc,
            verificationVector: vv
        });
    }

    function isBroadcasted(bytes32 groupIndex, uint nodeIndex) internal view returns (bool) {
        uint index = findNode(groupIndex, nodeIndex);
        return channels[groupIndex].broadcasted[index];
    }

    function findNode(bytes32 groupIndex, uint nodeIndex) internal view returns (uint) {
        uint[] memory nodesInGroup = IGroupsData(channels[groupIndex].dataAddress).getNodesInGroup(groupIndex);
        uint correctIndex = nodesInGroup.length;
        bool set = false;
        for (uint index = 0; index < nodesInGroup.length; index++) {
            if (nodesInGroup[index] == nodeIndex && !set) {
                correctIndex = index;
                set = true;
            }
        }
        return correctIndex;
    }

    function isNodeByMessageSender(uint nodeIndex, address from) internal view returns (bool) {
        address nodesDataAddress = contractManager.getContract("NodesData");
        return INodesData(nodesDataAddress).isNodeExist(from, nodeIndex);
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
            first = addmod(a.x, P - b.x, P);
        } else {
            first = P - addmod(b.x, P - a.x, P);
        }
        if (a.y >= b.y) {
            second = addmod(a.y, P - b.y, P);
        } else {
            second = P - addmod(b.y, P - a.y, P);
        }
        return Fp2({ x: first, y: second });
    }

    function mulFp2(Fp2 memory a, Fp2 memory b) internal pure returns (Fp2 memory) {
        uint aA = mulmod(a.x, b.x, P);
        uint bB = mulmod(a.y, b.y, P);
        return Fp2({
            x: addmod(aA, mulmod(P - 1, bB, P), P),
            y: addmod(mulmod(addmod(a.x, a.y, P), addmod(b.x, b.y, P), P), P - addmod(aA, bB, P), P)
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
            t2 = addmod(t0, P - t2, P);
        } else {
            t2 = P - addmod(t2, P - t0, P);
        }
        uint t3 = bigModExp(t2, P - 2);
        x.x = mulmod(a.x, t3, P);
        x.y = P - mulmod(a.y, t3, P);
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

    function doubleG2(Fp2 memory x1, Fp2 memory y1) internal view returns (Fp2 memory x3, Fp2 memory y3) {
        if (isG2Zero(x1, y1)) {
            x3 = x1;
            y3 = y1;
        } else {
            Fp2 memory s = mulFp2(scalarMulFp2(3, squaredFp2(x1)), inverseFp2(scalarMulFp2(2, y1)));
            x3 = minusFp2(squaredFp2(s), scalarMulFp2(2, x1));
            y3 = addFp2(y1, mulFp2(s, minusFp2(x3, x1)));
            y3.x = P - (y3.x % P);
            y3.y = P - (y3.y % P);
        }
    }

    function u1(Fp2 memory x1) internal pure returns (Fp2 memory) {
        return mulFp2(x1, squaredFp2(Fp2({ x: 1, y: 0 })));
    }

    function u2(Fp2 memory x2) internal pure returns (Fp2 memory) {
        return mulFp2(x2, squaredFp2(Fp2({ x: 1, y: 0 })));
    }

    function s1(Fp2 memory y1) internal pure returns (Fp2 memory) {
        return mulFp2(y1, mulFp2(Fp2({ x: 1, y: 0 }), squaredFp2(Fp2({ x: 1, y: 0 }))));
    }

    function s2(Fp2 memory y2) internal pure returns (Fp2 memory) {
        return mulFp2(y2, mulFp2(Fp2({ x: 1, y: 0 }), squaredFp2(Fp2({ x: 1, y: 0 }))));
    }

    function isEqual(
        Fp2 memory u1Value,
        Fp2 memory u2Value,
        Fp2 memory s1Value,
        Fp2 memory s2Value
    )
        internal
        pure
        returns (bool)
    {
        return (u1Value.x == u2Value.x && u1Value.y == u2Value.y && s1Value.x == s2Value.x && s1Value.y == s2Value.y);
    }

    function addG2(
        Fp2 memory x1,
        Fp2 memory y1,
        Fp2 memory x2,
        Fp2 memory y2
    )
        internal
        view
        returns (
            Fp2 memory x3,
            Fp2 memory y3
        )
    {
        if (isG2Zero(x1, y1)) {
            return (x2, y2);
        }
        if (isG2Zero(x2, y2)) {
            return (x1, y1);
        }
        if (
            isEqual(
                u1(x1),
                u2(x2),
                s1(y1),
                s2(y2)
            )
        ) {
            (x3, y3) = doubleG2(x1, y1);
        }

        Fp2 memory s = mulFp2(minusFp2(y2, y1), inverseFp2(minusFp2(x2, x1)));
        x3 = minusFp2(squaredFp2(s), addFp2(x1, x2));
        y3 = addFp2(y1, mulFp2(s, minusFp2(x3, x1)));
        y3.x = P - (y3.x % P);
        y3.y = P - (y3.y % P);
    }

    // function binstep(uint _a, uint _step) internal view returns (uint x) {
    //     x = 1;
    //     uint a = _a;
    //     uint step = _step;
    //     while (step > 0) {
    //         if (step % 2 == 1) {
    //             x = mulmod(x, a, P);
    //         }
    //         a = mulmod(a, a, P);
    //         step /= 2;
    //     }
    // }

    function mulG2(
        uint scalar,
        Fp2 memory x1,
        Fp2 memory y1
    )
        internal
        view
        returns (Fp2 memory x, Fp2 memory y)
    {
        uint step = scalar;
        x = Fp2({x: 0, y: 0});
        y = Fp2({x: 1, y: 0});
        Fp2 memory tmpX = x1;
        Fp2 memory tmpY = y1;
        while (step > 0) {
            if (step % 2 == 1) {
                (x, y) = addG2(
                    x,
                    y,
                    tmpX,
                    tmpY
                );
            }
            (tmpX, tmpY) = doubleG2(tmpX, tmpY);
            step >>= 1;
        }
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

    function loop(uint index, bytes memory verificationVector, uint loopIndex) internal view returns (Fp2 memory, Fp2 memory) {
        bytes32[4] memory vector;
        bytes32 vector1;
        assembly {
            vector1 := mload(add(verificationVector, add(32, mul(loopIndex, 128))))
        }
        vector[0] = vector1;
        assembly {
            vector1 := mload(add(verificationVector, add(64, mul(loopIndex, 128))))
        }
        vector[1] = vector1;
        assembly {
            vector1 := mload(add(verificationVector, add(96, mul(loopIndex, 128))))
        }
        vector[2] = vector1;
        assembly {
            vector1 := mload(add(verificationVector, add(128, mul(loopIndex, 128))))
        }
        vector[3] = vector1;
        return mulG2(
            bigModExp(index + 1, loopIndex),
            Fp2({x: uint(vector[1]), y: uint(vector[0])}),
            Fp2({x: uint(vector[3]), y: uint(vector[2])})
        );
    }

    function checkDKGVerification(Fp2 memory valX, Fp2 memory valY, bytes memory multipliedShare) internal pure returns (bool) {
        Fp2 memory tmpX;
        Fp2 memory tmpY;
        (tmpX, tmpY) = bytesToG2(multipliedShare);
        return valX.x == tmpX.y && valX.y == tmpX.x && valY.x == tmpY.y && valY.y == tmpY.x;
    }

    // function getMulShare(uint secret) public view returns (uint, uint, uint) {
    //     uint[3] memory inputToMul;
    //     uint[2] memory mulShare;
    //     inputToMul[0] = G1A;
    //     inputToMul[1] = G1B;
    //     inputToMul[2] = secret;
    //     bool success;
    //     assembly {
    //         success := staticcall(not(0), 7, inputToMul, 0x60, mulShare, 0x40)
    //     }
    //     require(success, "Multiplication failed");
    //     uint correct;
    //     if (!(mulShare[0] == 0 && mulShare[1] == 0)) {
    //         correct = P - (mulShare[1] % P);
    //     }
    //     return (mulShare[0], mulShare[1], correct);
    // }

    function checkCorrectMultipliedShare(bytes memory multipliedShare, uint secret) internal view returns (bool) {
        Fp2 memory tmpX;
        Fp2 memory tmpY;
        (tmpX, tmpY) = bytesToG2(multipliedShare);
        uint[3] memory inputToMul;
        uint[2] memory mulShare;
        inputToMul[0] = G1A;
        inputToMul[1] = G1B;
        inputToMul[2] = secret;
        bool success;
        assembly {
            success := staticcall(not(0), 7, inputToMul, 0x60, mulShare, 0x40)
        }
        require(success, "Multiplication failed");
        if (!(mulShare[0] == 0 && mulShare[1] == 0)) {
            mulShare[1] = P - (mulShare[1] % P);
        }

        require(isG1(G1A, G1B), "G1.one not in G1");
        require(isG1(mulShare[0], mulShare[1]), "mulShare not in G1");

        require(isG2(Fp2({x: G2A, y: G2B}), Fp2({x: G2C, y: G2D})), "G2.one not in G2");
        require(isG2(tmpX, tmpY), "tmp not in G2");

        uint[12] memory inputToPairing;
        inputToPairing[0] = mulShare[0];
        inputToPairing[1] = mulShare[1];
        inputToPairing[2] = G2B;
        inputToPairing[3] = G2A;
        inputToPairing[4] = G2D;
        inputToPairing[5] = G2C;
        inputToPairing[6] = G1A;
        inputToPairing[7] = G1B;
        inputToPairing[8] = tmpX.y;
        inputToPairing[9] = tmpX.x;
        inputToPairing[10] = tmpY.y;
        inputToPairing[11] = tmpY.x;
        uint[1] memory out;
        assembly {
            success := staticcall(not(0), 8, inputToPairing, mul(12, 0x20), out, 0x20)
        }
        require(success, "Pairing check failed");
        return out[0] != 0;
    }

    function bytesToPublicKey(bytes memory someBytes) internal pure returns (uint x, uint y) {
        bytes32 pkX;
        bytes32 pkY;
        assembly {
            pkX := mload(add(someBytes, 32))
            pkY := mload(add(someBytes, 64))
        }

        x = uint(pkX);
        y = uint(pkY);
    }

    function bytesToG2(bytes memory someBytes) internal pure returns (Fp2 memory x, Fp2 memory y) {
        bytes32 xa;
        bytes32 xb;
        bytes32 ya;
        bytes32 yb;
        assembly {
            xa := mload(add(someBytes, 32))
            xb := mload(add(someBytes, 64))
            ya := mload(add(someBytes, 96))
            yb := mload(add(someBytes, 128))
        }

        x = Fp2({x: uint(xa), y: uint(xb)});
        y = Fp2({x: uint(ya), y: uint(yb)});
    }
}
