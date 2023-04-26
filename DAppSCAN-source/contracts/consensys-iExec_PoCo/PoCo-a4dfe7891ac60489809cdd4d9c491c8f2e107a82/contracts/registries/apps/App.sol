pragma solidity ^0.6.0;

import "../RegistryEntry.sol";


contract App is RegistryEntry
{
	/**
	 * Members
	 */
	string  public  m_appName;
	string  public  m_appType;
	bytes   public  m_appMultiaddr;
	bytes32 public  m_appChecksum;
	bytes   public  m_appMREnclave;

	/**
	 * Constructor
	 */
	function initialize(
		string  memory _appName,
		string  memory _appType,
		bytes   memory _appMultiaddr,
		bytes32        _appChecksum,
		bytes   memory _appMREnclave)
	public
	{
		_initialize(msg.sender);
		m_appName      = _appName;
		m_appType      = _appType;
		m_appMultiaddr = _appMultiaddr;
		m_appChecksum  = _appChecksum;
		m_appMREnclave = _appMREnclave;
	}
}
