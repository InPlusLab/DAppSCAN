pragma solidity 0.6.12;

import "./interfaces/IdleToken.sol";
import "./PriceOracle.sol";

contract UnitrollerAdminStorage {
    /**
    * @notice Administrator for this contract
    */
    address public admin;

    /**
    * @notice Pending administrator for this contract
    */
    address public pendingAdmin;

    /**
    * @notice Active brains of Unitroller
    */
    address public comptrollerImplementation;

    /**
    * @notice Pending brains of Unitroller
    */
    address public pendingComptrollerImplementation;
}

contract IdleControllerStorage is UnitrollerAdminStorage {
  struct Market {
    /// @notice Whether or not this market is listed
    bool isListed;
    /// @notice Whether or not this market receives IDLE
    bool isIdled;
  }

  struct IdleMarketState {
    /// @notice The market's last updated idleSupplyIndex
    uint256 index;
    /// @notice The block number the index was last updated at
    uint256 block;
  }

  /// @notice Official mapping of idleTokens -> Market metadata
  /// @dev Used e.g. to determine if a market is supported
  mapping(address => Market) public markets;

  /// @notice A list of all markets
  IdleToken[] public allMarkets;
   /// @notice The rate at which the flywheel distributes IDLE, per block
  uint256 public idleRate;

  /// @notice The portion of compRate that each market currently receives
  mapping(address => uint256) public idleSpeeds;

  /// @notice The IDLE market supply state for each market
  mapping(address => IdleMarketState) public idleSupplyState;
  /// @notice The IDLE supply index for each market for each supplier as of the last time they accrued IDLE
  mapping(address => mapping(address => uint256)) public idleSupplierIndex;

  /// @notice The IDLE accrued but not yet transferred to each user
  mapping(address => uint256) public idleAccrued;

  /// @notice Oracle which gives the price of any given asset
  PriceOracle public oracle;

  /// @notice IDLE governance token address
  address public idleAddress;
}
