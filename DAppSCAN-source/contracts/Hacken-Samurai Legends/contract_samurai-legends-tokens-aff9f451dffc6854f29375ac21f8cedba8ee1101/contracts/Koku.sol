// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC20WithFees.sol";

/**
 * @title Contract that adds inflation and fees functionalities.
 * @author Leo
 */
contract Koku is ERC20WithFees {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    /**
     * @notice lastTimeAdminMintedAt The last time an admin minted new tokens.
     * adminMintableTokensPerSecond Amount of tokens that can be minted by an admin per second.
     * adminMintableTokensHardCap Maximum amount of tokens that can minted by an admin at once.
     */
    uint32 public lastTimeAdminMintedAt;
    uint112 public adminMintableTokensPerSecond = 0.005 * 1e9;
    uint112 public adminMintableTokensHardCap = 10_000 * 1e9;

    /**
     * @notice lastTimeGameMintedAt The last time the game minted new tokens.
     * gameMintableTokensPerSecond Amount of tokens that can be minted by the game per second.
     * gameMintableTokensHardCap Maximum amount of tokens that can minted by the game at once.
     */
    uint32 public lastTimeGameMintedAt;
    uint112 public gameMintableTokensPerSecond = 0.1 * 1e9;
    uint112 public gameMintableTokensHardCap = 10_000 * 1e9;

    constructor() ERC20WithFees("Koku", "KOKU")  {
        /**
         * @notice Grants ADMIN and MINTER roles to contract creator.
         */
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(MINTER_ROLE, msg.sender);

        /**
         * @notice Mints an initial 100k KOKU.
         */
        lastTimeAdminMintedAt = uint32(block.timestamp);
        _mint(msg.sender, 100_000 * 1e9);
    }

    function decimals() public view virtual override returns (uint8) {
        return 9;
    }

    /**
     * @notice Updates the adminMintableTokensPerSecond state variable.
     * @param amount The admin mintable tokens per second.
     */
    function setAdminMintableTokensPerSecond(uint112 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        adminMintableTokensPerSecond = amount;
        emit AdminMintableTokensPerSecondUpdated(amount);
    }

    /**
     * @notice Updates the adminMintableTokensHardCap state variable.
     * @param amount The admin mint hard cap.
     */
    function setAdminMintableTokensHardCap(uint112 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        adminMintableTokensHardCap = amount;
        emit AdminMintableTokensHardCapUpdated(amount);
    }

    /**
     * @notice Updates the gameMintableTokensPerSecond state variable.
     * @param amount The game mintable tokens per second.
     */
    function setGameMintableTokensPerSecond(uint112 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        gameMintableTokensPerSecond = amount;
        emit GameMintableTokensPerSecondUpdated(amount);
    }

    /**
     * @notice Updates the gameMintableTokensHardCap state variable.
     * @param amount The game mint hard cap.
     */
    function setGameMintableTokensHardCap(uint112 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        gameMintableTokensHardCap = amount;
        emit GameMintableTokensHardCapUpdated(amount);
    }

    /**
     * @notice Gives an admin the ability to mint more tokens.
     * @param amount Amount to mint.
     */
    function specialMint(uint amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(amount > 0, "Invalid input amount.");

        uint mintableTokens = getMintableTokens(lastTimeAdminMintedAt, adminMintableTokensPerSecond, adminMintableTokensHardCap);
        require(mintableTokens >= amount, "amount exceeds the mintable tokens amount.");

        _mint(msg.sender, amount);

        lastTimeAdminMintedAt = getLastTimeMintedAt(mintableTokens, amount, adminMintableTokensPerSecond);

        emit AdminBalanceIncremented(amount);
    }

    /**
     * @notice Increments the inputed account's balances by minting new tokens.
     * @param accounts Array of addresses to increment.
     * @param values Respective mint value of every account to increment.
     * @param valuesSum Total summation of all the values to mint.
     */
    function incrementBalances(address[] calldata accounts, uint[] calldata values, uint valuesSum) external onlyRole(MINTER_ROLE) {
        require(accounts.length == values.length, "Arrays must have the same length.");
        require(valuesSum > 0, "Invalid valuesSum amount.");

        uint mintableTokens = getMintableTokens(lastTimeGameMintedAt, gameMintableTokensPerSecond, gameMintableTokensHardCap);
        require(mintableTokens >= valuesSum, "valuesSum exceeds the mintable tokens amount.");

        uint sum = 0;
        for (uint i = 0; i < accounts.length; i++) {
            sum += values[i];
            require(mintableTokens >= sum, "sum exceeds the mintable tokens amount.");
            _mint(accounts[i], values[i]);
        }

        lastTimeGameMintedAt = getLastTimeMintedAt(mintableTokens, sum, gameMintableTokensPerSecond);

        emit UserBalancesIncremented(sum);
    }

    /**
     * @notice Computes the mintable tokens while taking the hardcap into account.
     * @param lastTimeMintedAt The last time new tokens minted at.
     * @param mintableTokensPerSecond Amount of tokens that can be minted per second.
     * @param mintableTokensHardCap Maximum amount of tokens that can minted at once.
     */
    function getMintableTokens(uint32 lastTimeMintedAt, uint112 mintableTokensPerSecond, uint112 mintableTokensHardCap) internal view returns (uint) {
        return min((block.timestamp - lastTimeMintedAt) * mintableTokensPerSecond, mintableTokensHardCap);
    }

    /**
     * @notice Computes the last time new tokens minted at by taking the current timestamp
     * and substracting from it the diff seconds between mintableTokens and mintedTokens.
     * @param mintableTokens Amount of tokens that can be minted.
     * @param mintedTokens Amount of tokens that have been be minted.
     * @param mintableTokensPerSecond Amount of tokens that can be minted per second.
     */
    function getLastTimeMintedAt(uint mintableTokens, uint mintedTokens, uint112 mintableTokensPerSecond) internal view returns (uint32) {
        return uint32(block.timestamp - (mintableTokens - mintedTokens) / mintableTokensPerSecond);
    }

    /**
     * @dev Returns the smallest of two numbers.
     */
    function min(uint a, uint b) internal pure returns (uint) {
        return a < b ? a : b;
    }

    event AdminMintableTokensPerSecondUpdated(uint amount);
    event AdminMintableTokensHardCapUpdated(uint amount);
    event GameMintableTokensPerSecondUpdated(uint amount);
    event GameMintableTokensHardCapUpdated(uint amount);
    event AdminBalanceIncremented(uint amount);
    event UserBalancesIncremented(uint amount);
}