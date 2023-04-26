pragma solidity ^0.6.0;

import "@iexec/interface/contracts/IexecHub.sol";
import "@iexec/solidity/contracts/Libs/SafeMathExtended.sol";
import "@iexec/solidity/contracts/ERC1538/ERC1538Store.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./libs/IexecLibCore_v5.sol";
import "./libs/IexecLibOrders_v5.sol";
import "./registries/apps/App.sol";
import "./registries/datasets/Dataset.sol";
import "./registries/workerpools/Workerpool.sol";
import "./registries/IRegistry.sol";

/****************************************************************************
 * WARNING: Be carefull when editing this file.                             *
 *                                                                          *
 * If you want add new variables for expanded features, add them at the     *
 * end, or (better?) create a Store_v2 that inherits from this Store.       *
 *                                                                          *
 * If in doubt, read about ERC1538 memory store.                            *
 ****************************************************************************/

abstract contract Store is ERC1538Store
{
	// Registries
	IRegistry internal m_appregistry;
	IRegistry internal m_datasetregistry;
	IRegistry internal m_workerpoolregistry;

	// Escrow
	IERC20  internal m_baseToken;
	string  internal m_name;
	string  internal m_symbol;
	uint8   internal m_decimals;
	uint256 internal m_totalSupply;
	mapping (address =>                     uint256 ) internal m_balances;
	mapping (address =>                     uint256 ) internal m_frozens;
	mapping (address => mapping (address => uint256)) internal m_allowances;

	// Poco - Constants
	uint256 internal constant CONTRIBUTION_DEADLINE_RATIO = 7;
	uint256 internal constant REVEAL_DEADLINE_RATIO       = 2;
	uint256 internal constant FINAL_DEADLINE_RATIO        = 10;
	uint256 internal constant WORKERPOOL_STAKE_RATIO      = 30;
	uint256 internal constant KITTY_RATIO                 = 10;
	uint256 internal constant KITTY_MIN                   = 1000000000; // TODO: 1RLC ?
	address internal constant KITTY_ADDRESS               = address(uint256(keccak256(bytes("iExecKitty"))) - 1);
	uint256 internal constant GROUPMEMBER_PURPOSE         = 4;
	bytes32 internal          EIP712DOMAIN_SEPARATOR;

	// Poco - Storage
	mapping(bytes32 =>                    address                      ) internal m_presigned;     // per order
	mapping(bytes32 =>                    uint256                      ) internal m_consumed;      // per order
	mapping(bytes32 =>                    IexecLibCore_v5.Deal         ) internal m_deals;         // per deal
	mapping(bytes32 =>                    IexecLibCore_v5.Task         ) internal m_tasks;         // per task
	mapping(bytes32 =>                    IexecLibCore_v5.Consensus    ) internal m_consensus;     // per task
	mapping(bytes32 => mapping(address => IexecLibCore_v5.Contribution)) internal m_contributions; // per task-worker
	mapping(address =>                    uint256                      ) internal m_workerScores;  // per worker

	// Poco - Settings
	address internal m_teebroker;
	uint256 internal m_callbackgas;

	// Categories
	IexecLibCore_v5.Category[] internal m_categories;

	// Backward compatibility
	IexecHubInterface internal m_v3_iexecHub;
	mapping(address => bool) internal m_v3_scoreImported;
}
