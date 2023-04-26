// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.6.12;

import "../Hermez.sol";

contract HermezTest is Hermez {
    event ReturnUint256(uint256);
    event ReturnBytes(bytes);

    function setLastIdx(uint48 newLastIdx) public {
        lastIdx = newLastIdx;
    }

    function getChainID() public view returns (uint256) {
        uint256 chainID;
        uint256 a = 0 % 6;
        assembly {
            chainID := chainid()
        }
        return chainID;
    }

    function token2USDTest(address tokenAddress, uint192 amount)
        public
        view
        returns (uint256)
    {
        return _token2USD(tokenAddress, amount);
    }

    function findBucketIdxTest(uint256 amountUSD)
        public
        view
        returns (uint256)
    {
        return _findBucketIdx(amountUSD);
    }

    function instantWithdrawalTest(address tokenAddress, uint192 amount)
        public
    {
        require(
            _processInstantWithdrawal(tokenAddress, amount),
            "Hermez::withdrawMerkleProof: INSTANT_WITHDRAW_WASTED_FOR_THIS_USD_RANGE"
        );
    }

    uint256 private constant _L1_USER_BYTES = 72;

    function changeCurrentIdx(uint32 newCurrentIdx) public {
        lastIdx = newCurrentIdx;
    }

    function calculateInputTest(
        uint32 newLastIdx,
        uint256 newStRoot,
        uint256 newExitRoot,
        bytes calldata compressedL1CoordinatorTx,
        bytes calldata l2TxsData,
        bytes calldata feeIdxCoordinator,
        bool l1Batch,
        uint8 verifierIdx
    ) public {
        emit ReturnUint256(
            _constructCircuitInput(
                newLastIdx,
                newStRoot,
                newExitRoot,
                l1Batch,
                verifierIdx
            )
        );
    }

    function forgeGasTest(
        uint48 newLastIdx,
        uint256 newStRoot,
        uint256 newExitRoot,
        bytes calldata encodedL1CoordinatorTx,
        bytes calldata l2TxsData,
        bytes calldata feeIdxCoordinator,
        uint8 verifierIdx,
        bool l1Batch,
        uint256[2] calldata proofA,
        uint256[2][2] calldata proofB,
        uint256[2] calldata proofC
    ) public {
        // Assure data availability from regular ethereum nodes
        // We include this line because it's easier to track the transaction data, as it will never be in an internal TX.
        // In general this makes no sense, as callling this function from another smart contract will have to pay the calldata twice.
        // But forcing, it avoids having to check.
        require(
            msg.sender == tx.origin,
            "forgeBatch can't be called as a internal transaction"
        );

        // ask the auction if this coordinator is allow to forge
        require(
            hermezAuctionContract.canForge(msg.sender, block.number) == true,
            "auction denied the forge"
        );

        if (!l1Batch) {
            require(
                block.number < (lastL1L2Batch + forgeL1L2BatchTimeout), // No overflow since forgeL1L2BatchTimeout is an uint8
                "L1L2Batch required"
            );
        }

        // calculate input
        uint256 input = _constructCircuitInput(
            newLastIdx,
            newStRoot,
            newExitRoot,
            l1Batch,
            verifierIdx
        );

        // verify proof
        require(
            rollupVerifiers[verifierIdx].verifierInterface.verifyProof(
                proofA,
                proofB,
                proofC,
                [input]
            ),
            "invalid rollup proof"
        );

        // update state
        lastForgedBatch++;
        lastIdx = newLastIdx;
        stateRootMap[lastForgedBatch] = newStRoot;
        exitRootsMap[lastForgedBatch] = newExitRoot;

        if (l1Batch) {
            // restart the timeout
            lastL1L2Batch = uint64(block.number);
            // clear current queue
            _clearQueue();
        }

        // auction must be aware that a batch is being forged
        hermezAuctionContract.forge(msg.sender);

        emit ForgeBatch(lastForgedBatch);
        emit ReturnUint256(gasleft());
    }

    function handleL1QueueTest(
        uint48 newLastIdx,
        uint256 newStRoot,
        uint256 newExitRoot,
        bytes calldata encodedL1CoordinatorTx,
        bytes calldata l2TxsData,
        bytes calldata feeIdxCoordinator,
        uint8 verifierIdx,
        bool l1Batch,
        uint256[2] calldata proofA,
        uint256[2][2] calldata proofB,
        uint256[2] calldata proofC
    ) public {
        uint256 ptr;
        bytes memory res = new bytes(_MAX_L1_TX * _L1_USER_TOTALBYTES);
        assembly {
            ptr := add(res, 0x20)
        }
        _buildL1Data(ptr, l1Batch);
        emit ReturnBytes(res);
    }
}
