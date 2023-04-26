pragma solidity ^0.6.0;

import "@iexec/solidity/contracts/ENStools/ENSReverseRegistration.sol";
import "./Registry.sol";


abstract contract RegistryEntry is ENSReverseRegistration
{
	IRegistry public registry;

	function _initialize(address _registry) internal
	{
		require(address(registry) == address(0), 'already initialized');
		registry = IRegistry(_registry);
	}

	function owner() public view returns (address)
	{
		return registry.ownerOf(uint256(address(this)));
	}

	modifier onlyOwner()
	{
		require(owner() == msg.sender, 'caller is not the owner');
		_;
	}

	function setName(address _ens, string calldata _name)
	external onlyOwner()
	{
		_setName(ENS(_ens), _name);
	}
}
