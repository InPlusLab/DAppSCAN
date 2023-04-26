// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./interfaces/IVotingPower.sol";
import "./interfaces/ITokenRegistry.sol";
import "./interfaces/IVotingPowerFormula.sol";
import "./interfaces/ILockManager.sol";
import "./lib/AccessControlEnumerable.sol";

/**
 * @title LockManager
 * @dev Manages voting power for stakes that are locked within the Eden ecosystem, but not in the Voting Power prism
 */
contract LockManager is AccessControlEnumerable, ILockManager {

    /// @notice Admin role to create voting power from locked stakes
    bytes32 public constant LOCKER_ROLE = keccak256("LOCKER_ROLE");

    // Official record of staked balances for each account > token > locked stake
    mapping (address => mapping (address => LockedStake)) internal lockedStakes;

    /// @notice Voting power contract
    IVotingPower public immutable votingPower;

    /// @notice modifier to restrict functions to only contracts that have been added as lockers
    modifier onlyLockers() {
        require(hasRole(LOCKER_ROLE, msg.sender), "Caller must have LOCKER_ROLE role");
        _;
    }

    /// @notice An event that's emitted when a user's staked balance increases
    event StakeLocked(address indexed user, address indexed token, uint256 indexed amount, uint256 votingPower);

    /// @notice An event that's emitted when a user's staked balance decreases
    event StakeUnlocked(address indexed user, address indexed token, uint256 indexed amount, uint256 votingPower);

    /**
     * @notice Create new LockManager contract
     * @param _votingPower VotingPower prism contract
     * @param _roleManager address that is in charge of assigning roles
     */
    constructor(address _votingPower, address _roleManager) {
        votingPower = IVotingPower(_votingPower);
        _setupRole(DEFAULT_ADMIN_ROLE, _roleManager);
    }

    /**
     * @notice Get total amount of tokens staked in contract by `staker`
     * @param staker The user with staked tokens
     * @param stakedToken The staked token
     * @return total amount staked
     */
    function getAmountStaked(address staker, address stakedToken) external view override returns (uint256) {
        return getStake(staker, stakedToken).amount;
    }

    /**
     * @notice Get total staked amount and voting power from `stakedToken` staked in contract by `staker`
     * @param staker The user with staked tokens
     * @param stakedToken The staked token
     * @return total staked
     */
    function getStake(address staker, address stakedToken) public view override returns (LockedStake memory) {
        return lockedStakes[staker][stakedToken];
    }

    /**
     * @notice Calculate the voting power that will result from locking `amount` of `token`
     * @param token token that will be locked
     * @param amount amount of token that will be locked
     * @return resulting voting power
     */
    function calculateVotingPower(address token, uint256 amount) public view override returns (uint256) {
        address registry = votingPower.tokenRegistry();
        require(registry != address(0), "LM::calculateVotingPower: registry not set");
        address tokenFormulaAddress = ITokenRegistry(registry).tokenFormulas(token);
        require(tokenFormulaAddress != address(0), "LM::calculateVotingPower: token not supported");
        
        IVotingPowerFormula tokenFormula = IVotingPowerFormula(tokenFormulaAddress);
        return tokenFormula.convertTokensToVotingPower(amount);
    }

    /**
     * @notice Grant voting power from locked `tokenAmount` of `token`
     * @param receiver recipient of voting power
     * @param token token that is locked
     * @param tokenAmount amount of token that is locked
     * @return votingPowerGranted amount of voting power granted
     */
    function grantVotingPower(
        address receiver, 
        address token, 
        uint256 tokenAmount
    ) external override onlyLockers returns (uint256 votingPowerGranted){
        votingPowerGranted = calculateVotingPower(token, tokenAmount);
        lockedStakes[receiver][token].amount = lockedStakes[receiver][token].amount + tokenAmount;
        lockedStakes[receiver][token].votingPower = lockedStakes[receiver][token].votingPower + votingPowerGranted;
        votingPower.addVotingPowerForLockedTokens(receiver, votingPowerGranted);
        emit StakeLocked(receiver, token, tokenAmount, votingPowerGranted);
    }

    /**
     * @notice Remove voting power by unlocking `tokenAmount` of `token`
     * @param receiver holder of voting power
     * @param token token that is being unlocked
     * @param tokenAmount amount of token that is being unlocked
     * @return votingPowerRemoved amount of voting power removed
     */
    function removeVotingPower(
        address receiver, 
        address token, 
        uint256 tokenAmount
    ) external override onlyLockers returns (uint256 votingPowerRemoved) {
        require(lockedStakes[receiver][token].amount >= tokenAmount, "LM::removeVotingPower: not enough tokens staked");
        LockedStake memory s = getStake(receiver, token);
        votingPowerRemoved = tokenAmount * s.votingPower / s.amount;
        lockedStakes[receiver][token].amount = lockedStakes[receiver][token].amount - tokenAmount;
        lockedStakes[receiver][token].votingPower = lockedStakes[receiver][token].votingPower - votingPowerRemoved;
        votingPower.removeVotingPowerForUnlockedTokens(receiver, votingPowerRemoved);
        emit StakeUnlocked(receiver, token, tokenAmount, votingPowerRemoved);
    }
}