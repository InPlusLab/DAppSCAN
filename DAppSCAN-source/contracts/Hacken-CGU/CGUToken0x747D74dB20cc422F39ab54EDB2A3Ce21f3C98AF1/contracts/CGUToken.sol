// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./access/Ownable.sol";
import "./interfaces/IERC677.sol";
import "./interfaces/IERC677Receiver.sol";

contract CGUToken is ERC20, IERC677, Ownable {
    event Lock(address account, uint256 amount, uint256 timestamp);
    event Burn(address account, uint256 amount);

    struct AccountLock {
        uint256 amount;
        uint256 timestamp;
    }

    mapping(address => AccountLock) public locks;

    bool private initialized;

    constructor(
        string memory tokenName,
        string memory tokenSymbol
    ) ERC20(tokenName, tokenSymbol) {}

    function init(address _initialHolder) external onlyOwner {
        require(!initialized, "Initialized");
        _mint(_initialHolder, 1000000000 * 10**8);
        initialized = true;
    }

    function _checksForLock(address account, uint256 amount) internal {
        if (locks[account].timestamp != 0) {
            uint256 lockedAmount = getLockedAmount(account);
            uint256 freeAmount = _balances[account] - lockedAmount;
            require(amount <= freeAmount, 'Such token amount is locked or you have insufficient balance');
        }
    }

    function lock(address account, uint256 amount, uint256 timestamp) external onlyOwner {
        require(locks[account].timestamp == 0, 'You can create a lock only once for address');
        _transfer(_msgSender(), account, amount);
        locks[account] = AccountLock(amount, timestamp);
        emit Lock(account, amount, timestamp);
    }

    function burn(uint256 amount) external {
        _checksForLock(_msgSender(), amount);
        _burn(_msgSender(), amount);
        emit Burn(_msgSender(), amount);
    }

// SWC-100-Function Default Visibility: L55
    function getLockedAmount(address account) public view returns (uint256) {
        return locks[account].timestamp > block.timestamp ? locks[account].amount : 0;
    }

    function transfer(address recipient, uint256 amount) public override(ERC20, IERC20) returns (bool) {
        _checksForLock(_msgSender(), amount);
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public override(ERC20, IERC20) returns (bool) {
        _checksForLock(sender, amount);
        _transfer(sender, recipient, amount);
        uint256 currentAllowance = _allowances[sender][_msgSender()];
        require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
    unchecked {
        _approve(sender, _msgSender(), currentAllowance - amount);
    }
        return true;
    }

// SWC-100-Function Default Visibility: L80
    function transferAndCall(address _to, uint _value, bytes memory _data) public override returns (bool success)
    {
        _checksForLock(_msgSender(), _value);
        transfer(_to, _value);
        emit Transfer(_msgSender(), _to, _value, _data);
        if (isContract(_to)) {
            contractFallback(_to, _value, _data);
        }
        return true;
    }

    function contractFallback(address _to, uint _value, bytes memory _data) private
    {
        IERC677Receiver receiver = IERC677Receiver(_to);
        receiver.onTokenTransfer(_msgSender(), _value, _data);
    }

    function isContract(address _addr) private view returns (bool hasCode)
    {
        uint length;
        assembly {length := extcodesize(_addr)}
        return length > 0;
    }

}
