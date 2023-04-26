// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../interfaces/IFeeCollector.sol";


contract TokenMock is ERC20, Ownable {
    // solhint-disable-next-line no-empty-blocks
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address account, uint256 amount) external onlyOwner {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) external onlyOwner {
        _burn(account, amount);
    }

    function getChainId() external view returns (uint256) {
        return block.chainid;
    }

    function updateReward(IFeeCollector _feeCollector, address referral, uint256 amount) public {
        transfer(address(_feeCollector), amount);
        _feeCollector.updateReward(referral, amount);
    }
}
