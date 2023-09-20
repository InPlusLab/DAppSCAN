// SPDX-License-Identifier: MIT

pragma solidity 0.7.4;

// SWC-135-Code With No Effects: L5 - L8
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "./ERC20Permit.sol";

// import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol";
// import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/SafeERC20.sol";
// import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/IERC20.sol";
// import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/math/SafeMath.sol";

/**
 * @title Token
 * @dev Burnable ERC20 Token
 */
contract CoinPokerChipsToken is ERC20Permit, Ownable {
    uint256 public constant MAX_CAP = 354786434702574732562458800;

    address public governance;

    event RecoverToken(address indexed token, address indexed destination, uint256 indexed amount);

    modifier onlyGovernance() {
        require(msg.sender == governance, "!governance");
        _;
    }

    constructor() ERC20("CoinPoker Chips", "CHP") {
        governance = msg.sender;
        _mint(governance, MAX_CAP);
    }

    /**
     * @notice Function to set governance contract
     * Owner is assumed to be governance
     * @param _governance Address of governance contract
     */
    function setGovernance(address _governance) public onlyGovernance {
        governance = _governance;
    }

    /**
     * @notice Function to recover funds
     * Owner is assumed to be governance or trusted party for helping users
     * @param token Address of token to be rescued
     * @param destination User address
     * @param amount Amount of tokens
     */
    function recoverToken(
        address token,
        address destination,
        uint256 amount
    ) external onlyGovernance {
        require(token != destination, "Invalid address");
        require(IERC20(token).transfer(destination, amount), "Retrieve failed");
        emit RecoverToken(token, destination, amount);
    }
}
