// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBase.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "./Roles.sol";

abstract contract Revealable is VRFConsumerBase, Roles {
    bool public randomseedRequested;
    bytes32 public keyHash;
    uint256 public revealBlock;
    uint256 public seed;
    string public revealedBaseURI;
    string public defaultURI;

    event RandomseedRequested(uint256 timestamp);
    event RandomseedFulfilmentSuccess(
        uint256 timestamp,
        bytes32 requestId,
        uint256 seed
    );
    event RandomseedFulfilmentFail(uint256 timestamp, bytes32 requestId);

    constructor(
        string memory _defaultUri,
        address _coordinator,
        address _linkToken,
        bytes32 _keyHash
    ) VRFConsumerBase(_coordinator, _linkToken) {
        defaultURI = _defaultUri;
        keyHash = _keyHash;
    }

    function setDefaultURI(string memory _defaultURI) external onlyOperator {
        require(!isRevealed(), "Already revealed");

        defaultURI = _defaultURI;
    }

    function setRevealBlock(uint256 blockNumber) external onlyOperator {
        revealBlock = blockNumber;
    }

    function setRevealedBaseURI(string memory _baseURI) external onlyOperator {
        revealedBaseURI = _baseURI;
    }

    function requestChainlinkVRF() external onlyOperator {
        require(!randomseedRequested, "Chainlink VRF already requested");
        require(
            LINK.balanceOf(address(this)) >= 2000000000000000000,
            "Insufficient LINK"
        );
        requestRandomness(keyHash, 2000000000000000000);
        randomseedRequested = true;
        emit RandomseedRequested(block.timestamp);
    }

    function fulfillRandomness(bytes32 requestId, uint256 randomNumber)
        internal
        override
    {
        if (randomNumber > 0) {
            seed = randomNumber;
            emit RandomseedFulfilmentSuccess(block.timestamp, requestId, seed);
        } else {
            seed = 1;
            emit RandomseedFulfilmentFail(block.timestamp, requestId);
        }
    }

    function isRevealed() public view returns (bool) {
        return seed > 0 && revealBlock > 0 && block.number > revealBlock;
    }

    function getShuffledId(
        uint256 totalSupply,
        uint256 maxSupply,
        uint256 tokenId,
        uint256 startIndex
    ) public view returns (string memory) {
        if (_msgSender() != owner()) {
            require(tokenId <= totalSupply, "Token not exists");
        }

        if (!isRevealed()) return "default";

        uint256[] memory metadata = new uint256[](maxSupply + 1);

        for (uint256 i = 1; i <= maxSupply; i += 1) {
            metadata[i] = i;
        }
        // SWC-128-DoS With Block Gas Limit: L98-104
        for (uint256 i = startIndex; i <= maxSupply; i += 1) {
            uint256 j = (uint256(keccak256(abi.encode(seed, i))) %
                (maxSupply)) + 1;

            if (j >= startIndex && j <= maxSupply) {
                (metadata[i], metadata[j]) = (metadata[j], metadata[i]);
            }
        }

        return Strings.toString(metadata[tokenId]);
    }
}
