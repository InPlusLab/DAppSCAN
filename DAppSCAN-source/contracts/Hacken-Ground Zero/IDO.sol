//SPDX-License-Identifier: MIT
// SWC-103-Floating Pragma: L4
pragma solidity ^0.8.4;

/**
 * @title IDO contract
 * @author gotbit
 */

//FOR TESTING PURPOSES
// SWC-135-Code With No Effects: L12 - L13
import "@openzeppelin/contracts/token/ERC1155/presets/ERC1155PresetMinterPauser.sol";
import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import "hardhat/console.sol";

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract IDO is Ownable {
    IERC20 public GZT;
    // is it started or not
    bool public idoStatus;

    uint256 public idoStart;
    uint256 public idoFinish;

    uint256 public cooldownToClaim;
    uint256 public allowedAmountToClaim;

    address[] public _allowedTokens;

    struct WhitelistInstance {
        uint256 maxAmountToClaim;
        bool isWhitelisted;
    }

    struct IDOParticipant {
        uint256 start;
        uint256 amountToClaim;
        uint256 claimedLastTime;
        uint256 claimedAmount;
        bool hasClaimed;
    }

    mapping(address => WhitelistInstance) public whitelist;
    mapping(address => IDOParticipant) public pool;

    mapping(IERC20 => bool) public allowedTokens;
    mapping(IERC20 => uint256[2]) public rates; // [numerator, denominator]

    event UserIsWhitelisted(address indexed user, uint256 indexed amount);
    event NewIDOParticipant(IERC20 indexed token, address indexed user, uint256 amount);

    constructor(IERC20 _IDO_TOKEN) {
        GZT = _IDO_TOKEN;
    }

    function participate(uint256 amountToSpent, IERC20 token) external {
        uint256[2] memory rate = rates[token];
        uint256 amountToClaim = ((amountToSpent * rate[0]) / rate[1]);

        require(idoStatus, "The IDO is not started!");
        require(block.timestamp < idoFinish, "The IDO is already finished!");
        require(pool[msg.sender].start == 0, "You're already participating in IDO");
        require(token.balanceOf(msg.sender) >= amountToSpent, "You don't have enough money!");
        require(whitelist[msg.sender].maxAmountToClaim >= amountToClaim, "You're not permited to claim this amount!");
        require(whitelist[msg.sender].isWhitelisted, "You're not whitelisted");

        require(allowedTokens[token], "This token is not allowed to participate");

        token.transferFrom(msg.sender, address(this), amountToSpent);

        pool[msg.sender] = IDOParticipant({
            start: block.timestamp,
            amountToClaim: amountToClaim,
            claimedLastTime: 0,
            claimedAmount: 0,
            hasClaimed: false
        });

        emit NewIDOParticipant(token, msg.sender, amountToSpent);
    }

// SWC-105-Unprotected Ether Withdrawal: L83 - L106
// SWC-107-Reentrancy: L84 - L107
    function claim() external {
        require(block.timestamp > idoFinish, "The IDO is not finished yet");
        require(pool[msg.sender].start != 0, "You're not participating in IDO");
        require(
            (block.timestamp - pool[msg.sender].claimedLastTime) > cooldownToClaim,
            "You are not allowed to claime more at this time"
        );
        require(!pool[msg.sender].hasClaimed, "You already claimed");

        if (
            (pool[msg.sender].claimedAmount < pool[msg.sender].amountToClaim) &&
            ((pool[msg.sender].amountToClaim - pool[msg.sender].claimedAmount) >= allowedAmountToClaim)
        ) {
            // SWC-104-Unchecked Call Return Value: L97
            GZT.transfer(msg.sender, allowedAmountToClaim);
            pool[msg.sender].claimedLastTime = block.timestamp;
        } else if (
            (pool[msg.sender].claimedAmount < pool[msg.sender].amountToClaim) &&
            ((pool[msg.sender].amountToClaim - pool[msg.sender].claimedAmount) < allowedAmountToClaim)
        ) {
            GZT.transfer(msg.sender, (pool[msg.sender].amountToClaim - pool[msg.sender].claimedAmount));
            pool[msg.sender].claimedLastTime = block.timestamp;
            pool[msg.sender].hasClaimed = true;
        }
    }

    function addUsersToWhitelist(address[] memory users, uint256[] memory amounts) external onlyOwner {
        require(users.length == amounts.length, "invalid array lengths");
        for (uint256 i = 0; i < amounts.length; i++) {
            whitelist[users[i]] = WhitelistInstance({maxAmountToClaim: amounts[i], isWhitelisted: true});
            emit UserIsWhitelisted(users[i], amounts[i]);
        }
    }

    function allowToken(
        IERC20 token,
        uint256 rateNumerator,
        uint256 rateDenominator
    ) external onlyOwner {
        allowedTokens[token] = true;
        rates[token] = [rateNumerator, rateDenominator];
        _allowedTokens.push(address(token));
    }

    function disallowTokens(IERC20 token) external onlyOwner {
        allowedTokens[token] = false;
    }

    function setIDO(
        uint256 start,
        uint256 finish,
        uint256 cooldown,
        uint256 _allowedAmountToClaim
    ) external onlyOwner {
        idoStatus = true;
        idoStart = start;
        idoFinish = finish;

        cooldownToClaim = cooldown;
        allowedAmountToClaim = _allowedAmountToClaim;
    }

// SWC-105-Unprotected Ether Withdrawal: L145 - l149
    function claimTheInvestments(IERC20 token, uint256 amount) external onlyOwner {
        require(block.timestamp > idoFinish, "The IDO is not finished yet");

// SWC-104-Unchecked Call Return Value: L150
        token.transfer(msg.sender, amount);
    }

    function infoBundler(address user)
        external
        view
        onlyOwner
        returns (
            WhitelistInstance memory whitelistInstance,
            IDOParticipant memory icoParticipantInstance,
            uint256[] memory _balancesOfAUser
        )
    {
        uint256[] memory balancesOfAUser;
        for (uint256 i = 0; i < _allowedTokens.length; i++) {
            IERC20 token = IERC20(_allowedTokens[i]);
            balancesOfAUser[i] = token.balanceOf(user);
        }

        return (whitelist[user], pool[user], balancesOfAUser);
    }
}