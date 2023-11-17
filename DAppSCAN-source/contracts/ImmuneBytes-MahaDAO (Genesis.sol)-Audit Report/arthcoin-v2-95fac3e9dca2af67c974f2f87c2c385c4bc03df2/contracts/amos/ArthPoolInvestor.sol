// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import '../utils/math/SafeMath.sol';
import '../ARTHX/IARTHX.sol';
import '../Arth/IARTH.sol';
import '../ERC20/ERC20.sol';
import '../Oracle/UniswapPairOracle.sol';
import '../access/AccessControl.sol';
import '../Arth/Pools/ArthPoolvAMM.sol';

// contract ArthPoolInvestor is AccessControl {
//     using SafeMath for uint256;

//     /* ========== STATE VARIABLES ========== */

//     ERC20 private collateralToken;
//     ArthPoolvAMM private pool;
//     address public collateralAddress;
//     address public pool_address;
//     address public ownerAddress;
//     address public timelock_address;

//     // AccessControl Roles
//     bytes32 private constant WITHDRAWAL_PAUSER = keccak256("WITHDRAWAL_PAUSER");

//     // AccessControl state variables
//     bool public withdrawalPaused = false;

//     uint256 public immutable missing_decimals;

//     // yearn vaults?

//     /* ========== MODIFIERS ========== */

//     modifier onlyByOwnerOrGovernance() {
//         require(msg.sender == timelock_address || msg.sender == ownerAddress, "You are not the owner or the governance timelock");
//         _;
//     }

//     modifier onlyPool() {
//         require(msg.sender == pool_address, "You are not the ArthPool");
//         _;
//     }

//     /* ========== CONSTRUCTOR ========== */

//     constructor(
//         address _pool_address,
//         address _collateralAddress,
//         address _creator_address,
//         address _timelock_address
//     ) public {
//         pool_address = _pool_address;
//         pool = ArthPoolvAMM(_pool_address);
//         collateralAddress = _collateralAddress;
//         collateralToken = ERC20(_collateralAddress);
//         timelock_address = _timelock_address;
//         ownerAddress = _creator_address;
//         missing_decimals = uint(18).sub(collateralToken.decimals());

//         _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
//         grantRole(WITHDRAWAL_PAUSER, timelock_address);
//         grantRole(WITHDRAWAL_PAUSER, ownerAddress);
//     }

//     /* ========== VIEWS ========== */

//     // BuyAndBurnARTHX

//     /* ========== PUBLIC FUNCTIONS ========== */

//     /* ========== RESTRICTED FUNCTIONS ========== */

//     function toggleWithdrawing() external {
//         require(hasRole(WITHDRAWAL_PAUSER, msg.sender));
//         withdrawalPaused = !withdrawalPaused;
//     }

//     function setTimelock(address new_timelock) external onlyByOwnerOrGovernance {
//         timelock_address = new_timelock;
//     }

//     function setOwner(address _ownerAddress) external onlyByOwnerOrGovernance {
//         ownerAddress = _ownerAddress;
//     }

//     function setPool(address _pool_address) external onlyByOwnerOrGovernance {
//         pool_address = _pool_address;
//         pool = ArthPoolvAMM(_pool_address);
//     }

//     /* ========== EVENTS ========== */

// }
