// SPDX-License-Identifier: UNLICENSED
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
        ERC20Detailed.initialize("Rari Stable Pool Token", "RSPT", 18);
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
            if (block.number < rariGovernanceTokenDistributor.distributionEndBlock()) rariGovernanceTokenDistributor.refreshDistributionSpeeds(IRariGovernanceTokenDistributor.RariPool.Stable);
        }

        emit GovernanceTokenDistributorSet(newContract);
    }

    /*
     * @notice Moves `amount` tokens from the caller's account to `recipient`.
     * @dev Claims RGT earned by the sender and `recipient` beforehand (so RariGovernanceTokenDistributor can continue distributing RGT considering the new RSPT balances).
     * @return A boolean value indicating whether the operation succeeded.
     */
    function transfer(address recipient, uint256 amount) public returns (bool) {
        // Claim RGT/set timestamp for initial transfer of RSPT to `recipient`
        if (address(rariGovernanceTokenDistributor) != address(0) && block.number > rariGovernanceTokenDistributor.distributionStartBlock()) {
            rariGovernanceTokenDistributor.distributeRgt(_msgSender(), IRariGovernanceTokenDistributor.RariPool.Stable);
            if (balanceOf(recipient) > 0) rariGovernanceTokenDistributor.distributeRgt(recipient, IRariGovernanceTokenDistributor.RariPool.Stable);
            else rariGovernanceTokenDistributor.beforeFirstPoolTokenTransferIn(recipient, IRariGovernanceTokenDistributor.RariPool.Stable);
        }

        // Transfer RSPT and returns true
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    /*
     * @notice Moves `amount` tokens from `sender` to `recipient` using the allowance mechanism. `amount` is then deducted from the caller's allowance.
     * @dev Claims RGT earned by `sender` and `recipient` beforehand (so RariGovernanceTokenDistributor can continue distributing RGT considering the new RSPT balances).
     * @return A boolean value indicating whether the operation succeeded.
     */
    function transferFrom(address sender, address recipient, uint256 amount) public returns (bool) {
        if (address(rariGovernanceTokenDistributor) != address(0) && block.number > rariGovernanceTokenDistributor.distributionStartBlock()) {
            // Claim RGT/set timestamp for initial transfer of RSPT to `recipient`
            rariGovernanceTokenDistributor.distributeRgt(sender, IRariGovernanceTokenDistributor.RariPool.Stable);
            if (balanceOf(recipient) > 0) rariGovernanceTokenDistributor.distributeRgt(recipient, IRariGovernanceTokenDistributor.RariPool.Stable);
            else rariGovernanceTokenDistributor.beforeFirstPoolTokenTransferIn(recipient, IRariGovernanceTokenDistributor.RariPool.Stable);
        }
    
        // Transfer RSPT, deduct from allowance, and return true
        _transfer(sender, recipient, amount);
        _approve(sender, _msgSender(), allowance(sender, _msgSender()).sub(amount, "ERC20: transfer amount exceeds allowance"));
        return true;
    }
    
    /**
     * @dev Creates `amount` tokens and assigns them to `account`, increasing the total supply. Caller must have the {MinterRole}.
     * @dev Claims RGT earned by `account` beforehand (so RariGovernanceTokenDistributor can continue distributing RGT considering the new RSPT balance of the caller).
     */
    function mint(address account, uint256 amount) public onlyMinter returns (bool) {
        if (address(rariGovernanceTokenDistributor) != address(0) && block.number > rariGovernanceTokenDistributor.distributionStartBlock()) {
            // Claim RGT/set timestamp for initial transfer of RSPT to `account`
            if (balanceOf(account) > 0) rariGovernanceTokenDistributor.distributeRgt(account, IRariGovernanceTokenDistributor.RariPool.Stable);
            else rariGovernanceTokenDistributor.beforeFirstPoolTokenTransferIn(account, IRariGovernanceTokenDistributor.RariPool.Stable);
        }

        // Mint RSPT and return true
        _mint(account, amount);
        return true;
    }

    /*
     * @notice Destroys `amount` tokens from the caller, reducing the total supply.
     * @dev Claims RGT earned by `account` beforehand (so RariGovernanceTokenDistributor can continue distributing RGT considering the new RSPT balance of the caller).
     */
    function burn(uint256 amount) public {
        // Claim RGT, then burn RSPT
        if (address(rariGovernanceTokenDistributor) != address(0) && block.number > rariGovernanceTokenDistributor.distributionStartBlock()) rariGovernanceTokenDistributor.distributeRgt(_msgSender(), IRariGovernanceTokenDistributor.RariPool.Stable);
        _burn(_msgSender(), amount);
    }

    /*
     * @notice Destroys `amount` tokens from `account`. `amount` is then deducted from the caller's allowance.
     * @dev Claims RGT earned by `account` beforehand (so RariGovernanceTokenDistributor can continue distributing RGT considering the new RSPT balance of `account`).
     */
    function burnFrom(address account, uint256 amount) public {
        // Claim RGT, then burn RSPT
        if (address(rariGovernanceTokenDistributor) != address(0) && block.number > rariGovernanceTokenDistributor.distributionStartBlock()) rariGovernanceTokenDistributor.distributeRgt(account, IRariGovernanceTokenDistributor.RariPool.Stable);
        _burnFrom(account, amount);
    }

    /*
     * @dev Destroys `amount` tokens from `account`. Caller must have the {MinterRole}.
     */
    function fundManagerBurnFrom(address account, uint256 amount) public onlyMinter {
        // Claim RGT, then burn RSPT
        if (address(rariGovernanceTokenDistributor) != address(0) && block.number > rariGovernanceTokenDistributor.distributionStartBlock()) rariGovernanceTokenDistributor.distributeRgt(account, IRariGovernanceTokenDistributor.RariPool.Stable);
        _burn(account, amount);
    }
}
