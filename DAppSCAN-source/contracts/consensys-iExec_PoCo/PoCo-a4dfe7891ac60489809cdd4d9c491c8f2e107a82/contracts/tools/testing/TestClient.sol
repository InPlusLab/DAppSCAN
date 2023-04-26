pragma solidity ^0.6.0;

import "@iexec/solidity/contracts/ERC1154/IERC1154.sol";


contract TestClient is IOracleConsumer
{
	event GotResult(bytes32 indexed id, bytes result);

	mapping(bytes32 => uint256) public gstore;
	mapping(bytes32 => bytes  ) public store;

	constructor()
	public
	{
	}

	function receiveResult(bytes32 id, bytes calldata result) external override
	{
		gstore[id] = gasleft();
		store[id]  = result;
		emit GotResult(id, result);
	}

}
