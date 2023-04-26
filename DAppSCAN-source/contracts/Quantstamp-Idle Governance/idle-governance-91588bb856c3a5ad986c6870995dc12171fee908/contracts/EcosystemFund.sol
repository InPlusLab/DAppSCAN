pragma solidity 0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title A simple contract for holding funds.
 */
contract EcosystemFund is Ownable {
  function transfer(address token, address to, uint256 value) external onlyOwner returns (bool) {
    return ERC20(token).transfer(to, value);
  }
}
