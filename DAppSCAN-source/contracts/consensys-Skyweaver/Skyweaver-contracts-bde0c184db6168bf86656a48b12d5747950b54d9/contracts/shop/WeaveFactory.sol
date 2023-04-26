pragma solidity ^0.5.16;
pragma experimental ABIEncoderV2;

import "../utils/Ownable.sol";
import "../interfaces/ISWSupplyManager.sol";
import "multi-token-standard/contracts/interfaces/IERC1155.sol";
import "multi-token-standard/contracts/utils/SafeMath.sol";

/**
 * This is a contract allowing owner to harvest weave based on time elapsed
 */
contract WeaveFactory is Ownable {
  using SafeMath for uint256;

  /***********************************|
  |        Variables && Events        |
  |__________________________________*/

  // Initiate Variables
  ISWSupplyManager internal factoryManager; //SkyWeaver Curencies Factory Manager Contract

  // Mapping variables
  uint256 internal weavePerSecond; // Amount of Weave that is created per second
  uint256 internal lastHarvest;    // Last timestamp weave was harvested
  uint256 internal weaveID;        // ID for weave, the only ID this contract can mint

  /***********************************|
  |               Events              |
  |__________________________________*/

  event WeaveHarvested(address recipient, uint256 amount);


  /***********************************|
  |            Constructor            |
  |__________________________________*/

  /**
   * @notice Create weave factory, link SW factory manager and set weekly weave limit
   * @param _factoryManagerAddr The address of the Skyweaver Factory Manager contract
   * @param _weavePerSecond     Amount of weave that is created per second
   * @param _weaveID            Weave's token ID
   */
  constructor(address _factoryManagerAddr, uint256 _weavePerSecond, uint256 _weaveID) public {

    //Input validation
    require(
      _factoryManagerAddr != address(0),
      "WeaveFactory#constructor: INVALID_INPUT"
    );

    // Set variables and constants
    factoryManager = ISWSupplyManager(_factoryManagerAddr);
    weavePerSecond = _weavePerSecond;
    lastHarvest = now;
    weaveID = _weaveID;
  }


  /***********************************|
  |         Management Methods        |
  |__________________________________*/

  /**
   * @notice Will mint weave and send it to _recipient
   * @param _recipient Address where the weave will be sent to
   * @param _data      Byte array that is passed if _recipient is a contract
   */
  function harvestWeave(address _recipient, bytes calldata _data) external onlyOwner() {
    // Calculate how much weave can be harvested
    uint256 time_since_last_harvest = now.sub(lastHarvest);
    uint256 weave_to_harvest = time_since_last_harvest.mul(weavePerSecond);

    // Update harvest time
    lastHarvest = now;

    // Mint weave
    factoryManager.mint(_recipient, weaveID, weave_to_harvest, _data);
    emit WeaveHarvested(_recipient, weave_to_harvest);
  }


  /***********************************|
  |      Receiver Method Handler      |
  |__________________________________*/

  /**
   * @notice Prevents receiving Ether
   */
  function () external {
    revert("UNSUPPORTED_METHOD");
  }

  /***********************************|
  |         Getter Functions          |
  |__________________________________*/

  /**
   * @notice Returns the address of the factory manager contract
   */
  function getFactoryManager() external view returns (address) {
    return address(factoryManager);
  }

  /**
   * @notice Returns Weave's token ID
   */
  function getWeaveID() external view returns (uint256) {
    return weaveID;
  }

  /**
   * @notice Returns the amount of weave that can be created per second
   */
  function getWeavePerSecond() external view returns (uint256) {
    return weavePerSecond;
  }

  /**
   * @notice Returns the last time weave was harvested
   */
  function getLastHarvest() external view returns (uint256) {
    return lastHarvest;
  }

  /**
   * @notice Returns the last time weave was harvested
   */
  function getAvailableWeave() external view returns (uint256) {
    uint256 time_since_last_harvest = now.sub(lastHarvest);
    return time_since_last_harvest.mul(weavePerSecond);
  }

}
