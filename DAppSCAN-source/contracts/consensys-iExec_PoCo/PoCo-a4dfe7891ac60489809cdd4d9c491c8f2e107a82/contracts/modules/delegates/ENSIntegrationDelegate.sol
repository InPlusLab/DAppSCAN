pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

import "@iexec/solidity/contracts/ENStools/ENSReverseRegistration.sol";
import "../DelegateBase.sol";
import "../interfaces/ENSIntegration.sol";


contract ENSIntegrationDelegate is ENSIntegration, ENSReverseRegistration, DelegateBase
{
	function setName(address _ens, string calldata _name)
	external override onlyOwner()
	{
		_setName(ENS(_ens), _name);
	}
}
