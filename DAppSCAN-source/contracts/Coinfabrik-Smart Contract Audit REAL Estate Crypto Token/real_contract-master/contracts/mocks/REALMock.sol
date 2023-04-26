pragma solidity ^0.4.11;

import '../REAL.sol';

// @dev REALMock mocks current block number

contract REALMock is REAL {

    function REALMock(address _tokenFactory) REAL(_tokenFactory) {}

    function getBlockNumber() internal constant returns (uint) {
        return mock_blockNumber;
    }

    function setMockedBlockNumber(uint _b) public {
        mock_blockNumber = _b;
    }

    uint mock_blockNumber = 1;
}
