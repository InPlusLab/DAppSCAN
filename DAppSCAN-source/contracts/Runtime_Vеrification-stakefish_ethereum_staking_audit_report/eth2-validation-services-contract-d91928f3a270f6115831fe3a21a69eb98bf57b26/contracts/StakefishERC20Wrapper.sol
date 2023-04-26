// Copyright (C) 2021 BITFISH LIMITED

// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

// SPDX-License-Identifier: GPL-3.0-only

pragma solidity 0.8.4;

import "./interfaces/IERC20.sol";
import "./interfaces/IStakefishServicesContract.sol";
import "./libraries/ReentrancyGuard.sol";
import "./libraries/Initializable.sol";

contract StakefishERC20Wrapper is IERC20, ReentrancyGuard, Initializable {
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    address payable private _serviceContract;
    string private _name;
    string private _symbol;
    uint256 private _totalSupply;
    uint256 private constant DECIMALS = 18;

    event Mint(address indexed sender, address indexed to, uint256 amount);
    event Redeem(address indexed sender, address indexed to, uint256 amount);

    function initialize(
        string memory name_,
        string memory symbol_,
        address payable serviceContract
    ) public initializer {
        _name = name_;
        _symbol = symbol_;
        _serviceContract = serviceContract;
    }

    // Wrapper functions

    function mintTo(address to, uint256 amount) public nonReentrant {
        require(amount > 0, "Amount can't be 0");

        _mint(to, amount);

        bool success = IStakefishServicesContract(_serviceContract).transferDepositFrom(
            msg.sender,
            address(this),
            amount
        );
        require(success, "Transfer deposit failed");

        emit Mint(msg.sender, to, amount);
    }

    function mint(uint256 amount) external {
        mintTo(msg.sender, amount);
    }

    function redeemTo(address to, uint256 amount) public nonReentrant {
        require(amount > 0, "Amount can't be 0");

        _burn(msg.sender, amount);

        bool success = IStakefishServicesContract(_serviceContract).transferDeposit(
            to,
            amount
        );
        require(success, "Transfer deposit failed");

        emit Redeem(msg.sender, to, amount);
    }

    function redeem(uint256 amount) external {
        redeemTo(msg.sender, amount);
    }

    // ERC20 functions

    function transfer(address to, uint256 amount) external override returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external override returns (bool) {
        uint256 currentAllowance = _allowances[from][msg.sender];
        // It will revert if underflow
        _approve(from, msg.sender, currentAllowance - amount);
        _transfer(from, to, amount);
       
        return true;
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) external returns (bool) {
        _approve(msg.sender, spender, _allowances[msg.sender][spender] + addedValue);
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) external returns (bool) {
        _approve(msg.sender, spender, _allowances[msg.sender][spender] - subtractedValue);
        return true;
    }

    function decimals() public pure returns (uint256) {
        return DECIMALS;
    }

    function name() public view returns (string memory) {
        return _name;    
    }

    function symbol() public view returns (string memory) {
        return _symbol;    
    }

    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address owner) public view override returns (uint256) {
        return _balances[owner];
    } 

    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal {
        require(to != address(0), "Transfer to the zero address");

        _balances[from] -= amount;
        _balances[to] += amount;

        emit Transfer(from, to, amount);
    }

    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) internal {
        require(spender != address(0), "Approve to the zero address");
        
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _mint(address owner, uint256 amount) internal {
        require(owner != address(0), "Mint to the zero address");

        _totalSupply += amount;
        _balances[owner] += amount;

        emit Transfer(address(0), owner, amount);
    }

    function _burn(address owner, uint256 amount) internal {
        require(owner != address(0), "Burn from the zero address");

        _totalSupply -= amount;
        _balances[owner] -= amount;

        emit Transfer(owner, address(0), amount);
    }
}
