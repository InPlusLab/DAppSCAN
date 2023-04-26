// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@yearn/contract-utils/contracts/utils/Governable.sol';
import '@yearn/contract-utils/contracts/utils/Manageable.sol';
import '../utils/OnlyStealthRelayer.sol';

contract StealthERC20 is ERC20, Governable, Manageable, OnlyStealthRelayer {
    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _mintAmount,
        address _stealthRelayer
    ) ERC20(_name, _symbol) Governable(msg.sender) Manageable(msg.sender) OnlyStealthRelayer(_stealthRelayer) {
        _mint(msg.sender, _mintAmount);
    }

    function stealthMint(address _to, uint256 _amount) public onlyStealthRelayer returns (bool _error) {
        _mint(_to, _amount);
        return false;
    }

    // Stealth Relayer Setters
    function setStealthRelayer(address _stealthRelayer) external override onlyGovernor {
        _setStealthRelayer(_stealthRelayer);
    }

    // Governable: restricted-access
    function setPendingGovernor(address _pendingGovernor) external override onlyGovernor {
        _setPendingGovernor(_pendingGovernor);
    }

    function acceptGovernor() external override onlyPendingGovernor {
        _acceptGovernor();
    }

    // Manageable: restricted-access
    function setPendingManager(address _pendingManager) external override onlyManager {
        _setPendingManager(_pendingManager);
    }

    function acceptManager() external override onlyPendingManager {
        _acceptManager();
    }
}
