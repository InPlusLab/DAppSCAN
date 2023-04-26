// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

contract BridgeToken is AccessControl, ERC20 {
    // Create a new role identifier for the minter role
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant DEPOSITOR_ROLE = keccak256("DEPOSITOR_ROLE");
    
    constructor(string memory name, string memory symbol)
    ERC20(name, symbol) {
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(MINTER_ROLE, _msgSender());
    }
    
    // Chainbridge functions
    function mint(address to, uint256 amount) external  {
        // Check that the calling account has the minter role
        require(hasRole(MINTER_ROLE, msg.sender), "Meter: Caller is not a minter");
        _mint(to, amount);
    }

    function burnFrom(address account, uint256 amount) external {
        uint256 currentAllowance = allowance(account, _msgSender());
        require(currentAllowance >= amount, "ERC20: burn amount exceeds allowance");
        _approve(account, _msgSender(), currentAllowance - amount);
        _burn(account, amount);
    }
    
    // Polygon functions
    /**
     * @notice called when token is deposited on root chain
     * @dev Should be callable only by ChildChainManager
     * Should handle deposit by minting the required amount for user
     * Make sure minting is done only by this function
     * @param user user address for whom deposit is being done
     * @param depositData abi encoded amount
     */
    function deposit(address user, bytes calldata depositData)
        external
    {
        require(hasRole(DEPOSITOR_ROLE, msg.sender), "Meter: Caller is not a minter");
        uint256 amount = abi.decode(depositData, (uint256));
        _mint(user, amount);
    }
    
    /**
     * @notice called when user wants to withdraw tokens back to root chain
     * @dev Should burn user"s tokens. This transaction will be verified when exiting on root chain
     * @param amount amount of tokens to withdraw
     */
    function withdraw(uint256 amount) external virtual {
        _burn(_msgSender(), amount);
    }
}