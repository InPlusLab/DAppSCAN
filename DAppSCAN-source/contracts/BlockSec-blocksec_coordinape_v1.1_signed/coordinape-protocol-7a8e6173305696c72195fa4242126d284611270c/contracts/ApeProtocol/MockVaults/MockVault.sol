// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.2;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockRegistry {

	address public governance;

	mapping(address => address) public latestVault;
	mapping(address => uint256) public numVaults;
	mapping(address => mapping(uint256 => address)) public vaults;

	constructor() {
		governance = msg.sender;
	}

	function addVault(address _token, address _vault) external {
		uint256 current = numVaults[_token];
		latestVault[_token] = _vault;
		numVaults[_token]++;
		vaults[_token][current] = _vault;
	}
}

contract MockVaultFactory {
	MockRegistry public registry;

	constructor(address _reg) {
		registry = MockRegistry(_reg);
	}

	function createVault(address _token, string memory _name, string memory _symbol) public returns(address) {
		MockVault newVault = new MockVault(_token, _name, _symbol);
		registry.addVault(_token, address(newVault));
		return address(newVault);
	}
}

contract MockVault is ERC20 {

	MockToken public token;

	uint256 public depositLimit;

	constructor (address _token, string memory _name, string memory _symbol) ERC20(_name, _symbol){
		token = MockToken(_token);
		depositLimit = type(uint256).max;
	}

	function totalAssets() external view returns (uint256) {
		return token.balanceOf(address(this));
	}

	function pricePerShare() public view returns(uint256) {
		if (totalSupply() == 0)
			return 10 ** uint256(decimals());
		else {
			return (10 ** uint256(decimals())) * token.balanceOf(address(this)) / totalSupply();
		}
	}

	function maxAvailableShares() external view returns (uint256) {
		return totalSupply();
	}

	function deposit() external returns (uint256) {
		return deposit(token.balanceOf(msg.sender));
	}

    function deposit(uint256 amount) public returns (uint256) {
		return deposit(amount, msg.sender);
	}

    function deposit(uint256 amount, address recipient) public returns (uint256 deposited) {
		depositLimit -= amount;
		if (totalSupply() == 0) {
			_mint(recipient, amount);
			deposited = amount;
		}
		else {
			uint256 _amount = amount * balanceOf(address(this)) / token.balanceOf(address(this));
			_mint(recipient, _amount);
			deposited = _amount;
		}
		token.transferFrom(msg.sender, address(this), amount);
	}

    // NOTE: Vyper produces multiple signatures for a given function with "default" args
    function withdraw() external returns (uint256) {
		return withdraw(balanceOf(msg.sender));
	}

    function withdraw(uint256 maxShares) public returns (uint256) {
		return withdraw(maxShares, msg.sender);
	}

    function withdraw(uint256 maxShares, address recipient) public returns (uint256 amount) {
		require(maxShares <= balanceOf(msg.sender) && maxShares > 0);
		amount = maxShares * token.balanceOf(address(this)) / totalSupply();
		_burn(msg.sender, maxShares);
		token.transfer(recipient, amount);
	}

	function goodHarvest(uint256 _apr) external {
		uint256 toMint = token.balanceOf(address(this)) * _apr / 100;
		token.mint(toMint);
	}

	function badHarvest(uint256 _apr) external {
		uint256 toBurn = token.balanceOf(address(this)) * _apr / 100;
		token.burn(toBurn);
	}
}

contract MockToken is ERC20 {

	constructor(string memory _name, string memory _symbol) ERC20(_name, _symbol) {}
	function mint(uint256 _amount) external {
		_mint(msg.sender, _amount);
	}

	function burn(uint256 _amount) external {
		_burn(msg.sender, _amount);
	}
}