// SPDX-FileCopyrightText: 2021 Tenderize <info@tenderize.me>

// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title Faucet for the Tokens
 */
contract TokenFaucet is Ownable {
    // Token
    ERC20 public token;

    // Amount of token sent to sender for a request
    uint256 public requestAmount;

    // Amount of time a sender must wait between requests
    uint256 public requestWait;

    // sender => timestamp at which sender can make another request
    mapping(address => uint256) public nextValidRequest;

    // Whitelist addresses that can bypass faucet request rate limit
    mapping(address => bool) public isWhitelisted;

    // Checks if a request is valid (sender is whitelisted or has waited the rate limit time)
    modifier validRequest() {
        require(isWhitelisted[msg.sender] || block.timestamp >= nextValidRequest[msg.sender]);
        _;
    }

    event Request(address indexed to, uint256 amount);

    /**
     * @notice Facuet constructor
     * @param _token Address of Token
     * @param _requestAmount Amount of token sent to sender for a request
     * @param _requestWait Amount of time a sender must wait between request (denominated in hours)
     */
    constructor(
        address _token,
        uint256 _requestAmount,
        uint256 _requestWait
    ) public {
        token = ERC20(_token);
        requestAmount = _requestAmount;
        requestWait = _requestWait;
    }

    /**
     * @notice Add an address to the whitelist
     * @param _addr Address to be whitelisted
     */
    function addToWhitelist(address _addr) external onlyOwner {
        isWhitelisted[_addr] = true;
    }

    /**
     * @notice Remove an address from the whitelist
     * @param _addr Address to be removed from whitelist
     */
    function removeFromWhitelist(address _addr) external onlyOwner {
        isWhitelisted[_addr] = false;
    }

    /**
     * @notice Request an amount of token to be sent to sender
     */
    function request() external validRequest {
        if (!isWhitelisted[msg.sender]) {
            nextValidRequest[msg.sender] = block.timestamp + requestWait * 1 hours;
        }

        token.transfer(msg.sender, requestAmount);

        emit Request(msg.sender, requestAmount);
    }
}
