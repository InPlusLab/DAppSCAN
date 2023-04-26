/***********************************************************
* This file is part of the Slock.it IoT Layer.             *
* The Slock.it IoT Layer contains:                         *
*   - USN (Universal Sharing Network)                      *
*   - INCUBED (Trustless INcentivized remote Node Network) *
************************************************************
* Copyright (C) 2016 - 2018 Slock.it GmbH                  *
* All Rights Reserved.                                     *
************************************************************
* You may use, distribute and modify this code under the   *
* terms of the license contract you have concluded with    *
* Slock.it GmbH.                                           *
* For information about liability, maintenance etc. also   *
* refer to the contract concluded with Slock.it GmbH.      *
************************************************************
* For more information, please refer to https://slock.it   *
* For questions, please contact info@slock.it              *
***********************************************************/

pragma solidity 0.5.10;
pragma experimental ABIEncoderV2;


/// @title Registry for blockhashes
contract BlockhashRegistry {

    /// a new blockhash and its number has been added to the contract
    event LogBlockhashAdded(uint indexed blockNr, bytes32 indexed bhash);

    /// maps the blocknumber to its blockhash
    mapping(uint => bytes32) public blockhashMapping;

    /// constructor, calls snapshot-function when contract get deployed as entry point
    /// @dev cannot be deployed in a genesis block
    constructor() public {
        snapshot();
    }

    /// @notice searches for an already existing snapshot
    /// @param _startNumber the blocknumber to start searching
    /// @param _numBlocks the number of blocks to search for
    /// @return the closes snapshot of found within the given range, 0 else
    function searchForAvailableBlock(uint _startNumber, uint _numBlocks) external view returns (uint) {

        for (uint i = _startNumber; i <= (_numBlocks + _startNumber); i++) {
            if (blockhashMapping[i] != 0x0) {
                return i;
            }
        }
    }

    /// @notice starts with a given blocknumber and its header and tries to recreate a (reverse) chain of blocks
    /// @notice only usable when the given blocknumber is already in the smart contract
    /// @notice it will be checked whether the provided chain is correct by using the reCalculateBlockheaders function
    /// @notice if successfull the last blockhash of the header will be added to the smart contract
    /// @param _blockNumber the block number to start recreation from
    /// @param _blockheaders array with serialized blockheaders in reverse order (youngest -> oldest) => (e.g. 100, 99, 98)
    /// @dev reverts when there is not parent block already stored in the contract
    /// @dev reverts when the chain of headers is incorrect
    /// @dev function is public due to the usage of a dynamic bytes array (not yet supported for external functions)
    function recreateBlockheaders(uint _blockNumber, bytes[] memory _blockheaders) public {

        bytes32 currentBlockhash = blockhashMapping[_blockNumber];
        require(currentBlockhash != 0x0, "parentBlock is not available");

        bytes32 calculatedHash = reCalculateBlockheaders(_blockheaders, currentBlockhash);
        require(calculatedHash != 0x0, "invalid headers");

        /// we should never fail this assert, as this would mean that we were able to recreate a invalid blockchain
        assert(_blockNumber > _blockheaders.length);
        uint bnr = _blockNumber - _blockheaders.length;
        blockhashMapping[bnr] = calculatedHash;
        emit LogBlockhashAdded(bnr, calculatedHash);
    }

    /// @notice stores a certain blockhash to the state
    /// @param _blockNumber the blocknumber to be stored
    /// @dev reverts if the block can't be found inside the evm
    function saveBlockNumber(uint _blockNumber) public {

        bytes32 bHash = blockhash(_blockNumber);

        require(bHash != 0x0, "block not available");

        blockhashMapping[_blockNumber] = bHash;
        emit LogBlockhashAdded(_blockNumber, bHash);
    }

    /// @notice stores the currentBlock-1 in the smart contract
    function snapshot() public {
        /// blockhash cannot return the current block, so we use the previous block
        saveBlockNumber(block.number-1);
    }

    /// @notice returns the blockhash and the parent blockhash from the provided blockheader
    /// @param _blockheader a serialized (rlp-encoded) blockheader
    /// @return the parent blockhash and the keccak256 of the provided blockheader (= the corresponding blockhash)
    function getParentAndBlockhash(bytes memory _blockheader) public pure returns (bytes32 parentHash, bytes32 bhash) {

        /// we need the 1st byte of the blockheader to calculate the position of the parentHash
        uint8 first = uint8(_blockheader[0]);

        /// calculates the offset
        /// by using the 1st byte (usually f9) and substracting f7 to get the start point of the parentHash information
        /// we also have to add "2" = 1 byte to it to skip the length-information
        require(first > 0xf7, "invalid offset");
        uint8 offset = first - 0xf7 + 2;

        /// we are using assembly because it's the most efficent way to access the parent blockhash within the rlp-encoded blockheader
        // solium-disable-next-line security/no-inline-assembly
        assembly { // solhint-disable-line no-inline-assembly
            // mstore to get the memory pointer of the blockheader to 0x20
            mstore(0x20, _blockheader)

            // we load the pointer we just stored
            // then we add 0x20 (32 bytes) to get to the start of the blockheader
            // then we add the offset we calculated
            // and load it to the parentHash variable
            parentHash :=mload(
                add(
                    add(
                        mload(0x20), 0x20
                    ), offset)
            )
        }
        bhash = keccak256(_blockheader);
    }

    /// @notice starts with a given blockhash and its header and tries to recreate a (reverse) chain of blocks
    /// @notice the array of the blockheaders have to be in reverse order (e.g. [100,99,98,97])
    /// @param _blockheaders array with serialized blockheaders in reverse order, i.e. from youngest to oldest
    /// @param _bHash blockhash of the 1st element of the _blockheaders-array
    /// @return 0x0 if the functions detects a wrong chaining of blocks, blockhash of the last element of the array otherwhise
    function reCalculateBlockheaders(bytes[] memory _blockheaders, bytes32 _bHash) public pure returns (bytes32 bhash) {

        bytes32 currentBlockhash = _bHash;
        bytes32 calcParent = 0x0;
        bytes32 calcBlockhash = 0x0;

        /// save to use for up to 200 blocks, exponential increase of gas-usage afterwards
        for (uint i = 0; i < _blockheaders.length; i++) {
            (calcParent, calcBlockhash) = getParentAndBlockhash(_blockheaders[i]);
            if (calcBlockhash != currentBlockhash) {
                return 0x0;
            }
            currentBlockhash = calcParent;
        }

        return currentBlockhash;
    }
}
