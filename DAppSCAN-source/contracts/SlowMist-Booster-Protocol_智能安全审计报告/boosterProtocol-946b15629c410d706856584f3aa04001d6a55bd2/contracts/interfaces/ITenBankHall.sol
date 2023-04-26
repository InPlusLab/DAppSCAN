// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ITenBankHall {
    function makeBorrowFrom(uint256 _pid, address _account, address _debtFrom, uint256 _value) external returns (uint256 bid);
}