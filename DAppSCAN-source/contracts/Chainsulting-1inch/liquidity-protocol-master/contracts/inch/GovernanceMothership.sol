// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "../interfaces/IGovernanceModule.sol";
import "../utils/BalanceAccounting.sol";


contract GovernanceMothership is Ownable, BalanceAccounting {
    using SafeMath for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;

    event Transfer(address indexed src, address indexed dst, uint256 amount);
    event AddModule(address indexed module);
    event RemoveModule(address indexed module);

    IERC20 public immutable inchToken;

    EnumerableSet.AddressSet private _modules;

    constructor(IERC20 _inchToken) public {
        inchToken = _inchToken;
    }

    function name() external pure returns(string memory) {
        return "1INCH Token (Staked)";
    }

    function symbol() external pure returns(string memory) {
        return "st1INCH";
    }

    function decimals() external pure returns(uint8) {
        return 18;
    }

    function stake(uint256 amount) external {
        require(amount > 0, "Empty stake is not allowed");

        inchToken.transferFrom(msg.sender, address(this), amount);
        _mint(msg.sender, amount);
        _notifyFor(msg.sender, balanceOf(msg.sender));
        emit Transfer(address(0), msg.sender, amount);
    }

    function unstake(uint256 amount) external {
        require(amount > 0, "Empty unstake is not allowed");

        inchToken.transfer(msg.sender, amount);
        _burn(msg.sender, amount);
        _notifyFor(msg.sender, balanceOf(msg.sender));
        emit Transfer(msg.sender, address(0), amount);
    }

    function notify() external {
        _notifyFor(msg.sender, balanceOf(msg.sender));
    }

    function notifyFor(address account) external {
        _notifyFor(account, balanceOf(account));
    }

    function batchNotifyFor(address[] memory accounts) external {
        uint256 modulesLength = _modules.length();
        uint256[] memory balances = new uint256[](accounts.length);
        for (uint256 j = 0; j < accounts.length; ++j) {
            balances[j] = balanceOf(accounts[j]);
        }
        for (uint256 i = 0; i < modulesLength; ++i) {
            IGovernanceModule(_modules.at(i)).notifyStakesChanged(accounts, balances);
        }
    }

    function addModule(address module) external onlyOwner {
        require(_modules.add(module), "Module already registered");
        emit AddModule(module);
    }

    function removeModule(address module) external onlyOwner {
        require(_modules.remove(module), "Module was not registered");
        emit RemoveModule(module);
    }

    function _notifyFor(address account, uint256 balance) private {
        bytes32[] memory cached = _modules._inner._values;
        for (uint256 i = 0; i < cached.length; ++i) {
            IGovernanceModule(address(uint256(cached[i]))).notifyStakeChanged(account, balance);
        }
    }
}
