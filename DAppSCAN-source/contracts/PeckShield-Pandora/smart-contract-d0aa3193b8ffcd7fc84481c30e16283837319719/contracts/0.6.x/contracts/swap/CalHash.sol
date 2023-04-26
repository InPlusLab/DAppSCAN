//SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.5.16;
import './SwapPair.sol';

contract CalHash {
    function getInitHash() public pure returns(bytes32){
        bytes memory bytecode = type(SwapPair).creationCode;
        return keccak256(abi.encodePacked(bytecode));
    }
}