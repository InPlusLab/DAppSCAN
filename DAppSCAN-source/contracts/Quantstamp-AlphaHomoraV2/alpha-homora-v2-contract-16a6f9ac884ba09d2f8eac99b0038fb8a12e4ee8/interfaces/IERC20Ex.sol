pragma solidity 0.6.12;

import 'OpenZeppelin/openzeppelin-contracts@3.2.0/contracts/token/ERC20/IERC20.sol';

// Export IERC20 interface for mainnet-fork testing.
interface IERC20Ex is IERC20 {
  function name() external view returns (string memory);
}
