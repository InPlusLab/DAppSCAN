// 0.5.1-c8a2
// Enable optimization
pragma solidity ^0.5.0;
// SWC-103-Floating Pragma: L3
// SWC-102-Outdated Compiler Version: L3
import "./ERC20.sol";
import "./ERC20Detailed.sol";

/**
 * @title SimpleToken
 * @dev Very simple ERC20 Token example, where all tokens are pre-assigned to the creator.
 * Note they can later distribute these tokens as they wish using `transfer` and other
 * `ERC20` functions.
 */
contract Token is ERC20, ERC20Detailed {

    /**
     * @dev Constructor that gives msg.sender all of existing tokens.
     */
    constructor () public ERC20Detailed("MRWEB", "AMA", 6) {
        _mint(msg.sender, 100000000 * (10 ** uint256(decimals())));
    }
}