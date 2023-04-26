/**
 * COPYRIGHT © 2020 RARI CAPITAL, INC. ALL RIGHTS RESERVED.
 * Anyone is free to integrate the public (i.e., non-administrative) application programming interfaces (APIs) of the official Ethereum smart contract instances deployed by Rari Capital, Inc. in any application (commercial or noncommercial and under any license), provided that the application does not abuse the APIs or act against the interests of Rari Capital, Inc.
 * Anyone is free to study, review, and analyze the source code contained in this package.
 * Reuse (including deployment of smart contracts other than private testing on a private network), modification, redistribution, or sublicensing of any source code contained in this package is not permitted without the explicit permission of David Lucid of Rari Capital, Inc.
 * No one is permitted to use the software for any purpose other than those allowed by this license.
 * This license is liable to change at any time at the sole discretion of David Lucid of Rari Capital, Inc.
 */

pragma solidity 0.5.17;

import "@openzeppelin/upgrades/contracts/Initializable.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/ERC20Detailed.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/ERC20Mintable.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/ERC20Burnable.sol";

import "./interfaces/IRariGovernanceTokenDistributor.sol";

/**
 * @title RariFundToken
 * @author David Lucid <david@rari.capital> (https://github.com/davidlucid)
 * @notice RariFundToken is the ERC20 token contract accounting for the ownership of RariFundController's funds.
 */
contract RariFundToken is Initializable, ERC20, ERC20Detailed, ERC20Mintable, ERC20Burnable {
    using SafeMath for uint256;

    /**
     * @dev Initializer for RariFundToken.
     */
    function initialize() public initializer {
        ERC20Detailed.initialize("Rari Yield Pool Token", "RYPT", 18);
        ERC20Mintable.initialize(msg.sender);
    }

    /**
     * @dev Contract of the RariGovernanceTokenDistributor.
     */
    IRariGovernanceTokenDistributor public rariGovernanceTokenDistributor;

    /**
     * @dev Emitted when the GovernanceTokenDistributorSet of the RariFundManager is set or upgraded.
     */
    event GovernanceTokenDistributorSet(address newContract);

    /**
     * @dev Sets or upgrades the RariGovernanceTokenDistributor of the RariFundToken. Caller must have the {MinterRole}.
     * @param newContract The address of the new RariGovernanceTokenDistributor contract.
     * @param force Boolean indicating if we should not revert on validation error.
     */
    function setGovernanceTokenDistributor(address payable newContract, bool force) external onlyMinter {        
        if (!force && address(rariGovernanceTokenDistributor) != address(0)) {
            require(rariGovernanceTokenDistributor.disabled(), "The old governance token distributor contract has not been disabled. (Set `force` to true to avoid this error.)");
            require(newContract != address(0), "By default, the governance token distributor cannot be set to the zero address. (Set `force` to true to avoid this error.)");
        }

        rariGovernanceTokenDistributor = IRariGovernanceTokenDistributor(newContract);

        if (newContract != address(0)) {
            if (!force) require(block.number <= rariGovernanceTokenDistributor.distributionStartBlock(), "The distribution period has already started. (Set `force` to true to avoid this error.)");
            if (block.number < rariGovernanceTokenDistributor.distributionEndBlock()) rariGovernanceTokenDistributor.refreshDistributionSpeeds(IRariGovernanceTokenDistributor.RariPool.Yield);
        }

        emit GovernanceTokenDistributorSet(newContract);
    }

    /*
     * @notice Moves `amount` tokens from the caller's account to `recipient`.
     * @dev Claims RGT earned by the sender and `recipient` beforehand (so RariGovernanceTokenDistributor can continue distributing RGT considering the new RYPT balances).
     * @return A boolean value indicating whether the operation succeeded.
     */
    function transfer(address recipient, uint256 amount) public returns (bool) {
        // Claim RGT/set timestamp for initial transfer of RYPT to `recipient`
        if (address(rariGovernanceTokenDistributor) != address(0) && block.number > rariGovernanceTokenDistributor.distributionStartBlock()) {
            rariGovernanceTokenDistributor._claimRgt(_msgSender(), IRariGovernanceTokenDistributor.RariPool.Yield);
            if (balanceOf(recipient) > 0) rariGovernanceTokenDistributor._claimRgt(recipient, IRariGovernanceTokenDistributor.RariPool.Yield);
            else rariGovernanceTokenDistributor.beforeFirstPoolTokenTransferIn(recipient, IRariGovernanceTokenDistributor.RariPool.Yield);
        }

        // Transfer RYPT and returns true
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    /*
     * @notice Moves `amount` tokens from `sender` to `recipient` using the allowance mechanism. `amount` is then deducted from the caller's allowance.
     * @dev Claims RGT earned by `sender` and `recipient` beforehand (so RariGovernanceTokenDistributor can continue distributing RGT considering the new RYPT balances).
     * @return A boolean value indicating whether the operation succeeded.
     */
    function transferFrom(address sender, address recipient, uint256 amount) public returns (bool) {
        if (address(rariGovernanceTokenDistributor) != address(0) && block.number > rariGovernanceTokenDistributor.distributionStartBlock()) {
            // Claim RGT/set timestamp for initial transfer of RYPT to `recipient`
            rariGovernanceTokenDistributor._claimRgt(sender, IRariGovernanceTokenDistributor.RariPool.Yield);
            if (balanceOf(recipient) > 0) rariGovernanceTokenDistributor._claimRgt(recipient, IRariGovernanceTokenDistributor.RariPool.Yield);
            else rariGovernanceTokenDistributor.beforeFirstPoolTokenTransferIn(recipient, IRariGovernanceTokenDistributor.RariPool.Yield);
        }
    
        // Transfer RYPT, deduct from allowance, and return true
        _transfer(sender, recipient, amount);
        _approve(sender, _msgSender(), allowance(sender, _msgSender()).sub(amount, "ERC20: transfer amount exceeds allowance"));
        return true;
    }
    
    /**
     * @dev Creates `amount` tokens and assigns them to `account`, increasing the total supply. Caller must have the {MinterRole}.
     * @dev Claims RGT earned by `account` beforehand (so RariGovernanceTokenDistributor can continue distributing RGT considering the new RYPT balance of the caller).
     */
    function mint(address account, uint256 amount) public onlyMinter returns (bool) {
        if (address(rariGovernanceTokenDistributor) != address(0) && block.number > rariGovernanceTokenDistributor.distributionStartBlock()) {
            // Claim RGT/set timestamp for initial transfer of RYPT to `account`
            if (balanceOf(account) > 0) rariGovernanceTokenDistributor._claimRgt(account, IRariGovernanceTokenDistributor.RariPool.Yield);
            else rariGovernanceTokenDistributor.beforeFirstPoolTokenTransferIn(account, IRariGovernanceTokenDistributor.RariPool.Yield);
        }

        // Mint RYPT and return true
        _mint(account, amount);
        return true;
    }

    /*
     * @notice Destroys `amount` tokens from the caller, reducing the total supply.
     * @dev Claims RGT earned by `account` beforehand (so RariGovernanceTokenDistributor can continue distributing RGT considering the new RYPT balance of the caller).
     */
    function burn(uint256 amount) public {
        // Claim RGT, then burn RYPT
        if (address(rariGovernanceTokenDistributor) != address(0) && block.number > rariGovernanceTokenDistributor.distributionStartBlock()) rariGovernanceTokenDistributor._claimRgt(_msgSender(), IRariGovernanceTokenDistributor.RariPool.Yield);
        _burn(_msgSender(), amount);
    }

    /*
     * @notice Destroys `amount` tokens from `account`. `amount` is then deducted from the caller's allowance.
     * @dev Claims RGT earned by `account` beforehand (so RariGovernanceTokenDistributor can continue distributing RGT considering the new RYPT balance of `account`).
     */
    function burnFrom(address account, uint256 amount) public {
        // Claim RGT, then burn RYPT
        if (address(rariGovernanceTokenDistributor) != address(0) && block.number > rariGovernanceTokenDistributor.distributionStartBlock()) rariGovernanceTokenDistributor._claimRgt(account, IRariGovernanceTokenDistributor.RariPool.Yield);
        _burnFrom(account, amount);
    }

    /*
     * @dev Destroys `amount` tokens from `account`. Caller must have the {MinterRole}.
     */
    function fundManagerBurnFrom(address account, uint256 amount) public onlyMinter {
        // Claim RGT, then burn RYPT
        if (address(rariGovernanceTokenDistributor) != address(0) && block.number > rariGovernanceTokenDistributor.distributionStartBlock()) rariGovernanceTokenDistributor._claimRgt(account, IRariGovernanceTokenDistributor.RariPool.Yield);
        _burn(account, amount);
    }
}
