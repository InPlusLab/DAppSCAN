// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.5;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "./interfaces/ISportsIconPrivateVesting.sol";

contract SportsIconPrivateVesting is ISportsIconPrivateVesting {
    using SafeMath for uint256;

    mapping(address => uint256) public override vestedTokensOf;
    mapping(address => uint256) public vestedTokensOfPrivileged;
    mapping(address => uint256) public override claimedOf;
    IERC20 public override token;
    uint256 private startTime;
    uint256 public vestingPeriod;

    constructor(
        address _tokenAddress,
        address[] memory holders,
        uint256[] memory balances,
        address[] memory privilegedHolders,
        uint256[] memory privilegedBalances,
        uint256 _vestingPeriod
    ) {
        require(
            (holders.length == balances.length) &&
                (privilegedHolders.length == privilegedBalances.length),
            "Constructor :: Holders and balances differ"
        );
        require(
            _tokenAddress != address(0x0),
            "Constructor :: Invalid token address"
        );
        require(_vestingPeriod > 0, "Constructor :: Invalid vesting period");

        token = IERC20(_tokenAddress);

        for (uint256 i = 0; i < holders.length; i++) {
            if ((i <= privilegedHolders.length - 1) && (privilegedHolders.length > 0)) {
                vestedTokensOfPrivileged[privilegedHolders[i]] = privilegedBalances[i];
            }

            vestedTokensOf[holders[i]] = balances[i];
        }

        vestingPeriod = _vestingPeriod;
        startTime = block.timestamp;
    }

    function freeTokens(address user) public view override returns (uint256) {
        uint256 owed = calculateOwed(user);
        return owed.sub(claimedOf[user]);
    }

    function claim() external override returns (uint256) {
        uint256 tokens = freeTokens(msg.sender);
        claimedOf[msg.sender] = claimedOf[msg.sender].add(tokens);
//SWC-104-Unchecked Call Return Value:L60
        token.transfer(msg.sender, tokens);

        emit LogTokensClaimed(msg.sender, tokens);

        return tokens;
    }

    function calculateOwed(address user) internal view returns (uint256 owed) {
        if (vestedTokensOfPrivileged[user] > 0) {
            return vestedTokensOfPrivileged[user];
        }

        uint256 periodsPassed = ((block.timestamp.sub(startTime)).div(30 days));
        if (periodsPassed > vestingPeriod) {
            periodsPassed = vestingPeriod;
        }
        uint256 vestedTokens = vestedTokensOf[user];
        uint256 initialUnlock = vestedTokens.div(10);
        uint256 remainder = vestedTokens.sub(initialUnlock);
        uint256 monthlyUnlock = periodsPassed.mul(remainder).div(vestingPeriod);
        return initialUnlock.add(monthlyUnlock);
    }
}
