// SPDX-License-Identifier: MIT
//SWC-103-Floating Pragma:L3
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../RFOXNFTStandard.sol";

contract RFOXFactoryStandard is Ownable {
    address[] public allNFTs;

    event NewRFOXNFT(address indexed nftAddress, ParamStructs.StandardParams params);

    function createNFT(ParamStructs.StandardParams calldata _params) external onlyOwner returns (address newNFT) {
        ParamStructs.StandardParams memory params = _params;
        bytes memory bytecode = type(RFOXNFTStandard).creationCode;
        bytes32 salt = keccak256(
            abi.encodePacked(allNFTs.length, params.name, params.symbol)
        );

        assembly {
            newNFT := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }

        RFOXNFTStandard(newNFT).initialize(params);

        allNFTs.push(address(newNFT));

        emit NewRFOXNFT(newNFT, params);

        return address(newNFT);
    }
}
