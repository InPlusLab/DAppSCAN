pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

import "@iexec/solidity/contracts/ERC734/IERC734.sol";
import "@iexec/solidity/contracts/ERC1271/IERC1271.sol";
import "../DelegateBase.sol";


contract SignatureVerifier is DelegateBase
{
	using IexecLibOrders_v5 for bytes32;

	bytes4 constant internal MAGICVALUE = 0x20c13b0b;

	function _isContract(address _addr)
	internal view returns (bool)
	{
		uint32 size;
		assembly { size := extcodesize(_addr) }
		return size > 0;
	}

	function _addrToKey(address _addr)
	internal pure returns (bytes32)
	{
		return bytes32(uint256(_addr));
	}

	function _checkIdentity(address _identity, address _candidate, uint256 _purpose)
	internal view returns (bool valid)
	{
		return _identity == _candidate || IERC734(_identity).keyHasPurpose(_addrToKey(_candidate), _purpose); // Simple address || ERC 734 identity contract
	}

	function _checkSignature(address _identity, bytes32 _hash, bytes memory _signature)
	internal view returns (bool)
	{
		if (_isContract(_identity))
		{
			return IERC1271(_identity).isValidSignature(_hash, _signature) == MAGICVALUE;
		}
		else
		{
			return _hash.recover(_signature) == _identity;
		}
	}

	function _checkPresignature(address _identity, bytes32 _hash)
	internal view returns (bool)
	{
		return _identity != address(0) && _identity == m_presigned[_hash];
	}

	function _checkPresignatureOrSignature(address _identity, bytes32 _hash, bytes memory _signature)
	internal view returns (bool)
	{
		return _checkPresignature(_identity, _hash) || _checkSignature(_identity, _hash, _signature);
	}
}
