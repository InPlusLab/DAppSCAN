// SPDX-License-Identifier: MIT
pragma solidity 0.7.5;

import "@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/introspection/IERC165.sol";

/**
 * @title Chainlink Oracle
 * @author Cryptex.finance
 * @notice Contract in charge or reading the information from a Chainlink Oracle. TCAP contracts read the price directly from this contract. More information can be found on Chainlink Documentation
 */
contract ChainlinkOracle is Ownable, IERC165 {
  AggregatorV3Interface internal aggregatorContract;

  /*
   * setReferenceContract.selector ^
   * getLatestAnswer.selector ^
   * getLatestTimestamp.selector ^
   * getPreviousAnswer.selector ^
   * getPreviousTimestamp.selector =>  0x85be402b
   */
  bytes4 private constant _INTERFACE_ID_CHAINLINK_ORACLE = 0x85be402b;

  /*
   * bytes4(keccak256('supportsInterface(bytes4)')) == 0x01ffc9a7
   */
  bytes4 private constant _INTERFACE_ID_ERC165 = 0x01ffc9a7;

  /**
   * @notice Called once the contract is deployed.
   * Set the Chainlink Oracle as an aggregator.
   */
  constructor(address _aggregator, address _owner) {
		require(_aggregator != address(0) && _owner != address(0), "address can't be 0");
    aggregatorContract = AggregatorV3Interface(_aggregator);
	  transferOwnership(_owner);
  }

  /**
   * @notice Changes the reference contract.
   * @dev Only owner can call it.
   */
  function setReferenceContract(address _aggregator) public onlyOwner() {
    aggregatorContract = AggregatorV3Interface(_aggregator);
  }

  /**
   * @notice Returns the latest answer from the reference contract.
   * @return price
   */
  function getLatestAnswer() public view returns (int256) {
    (
      uint80 roundID,
      int256 price,
      ,
      uint256 timeStamp,
      uint80 answeredInRound
    ) = aggregatorContract.latestRoundData();
    require(
      timeStamp != 0,
      "ChainlinkOracle::getLatestAnswer: round is not complete"
    );
    require(
      answeredInRound >= roundID,
      "ChainlinkOracle::getLatestAnswer: stale data"
    );
    return price;
  }

  /**
   * @notice Returns the latest round from the reference contract.
   */
  function getLatestRound()
    public
    view
    returns (
      uint80,
      int256,
      uint256,
      uint256,
      uint80
    )
  {
    (
      uint80 roundID,
      int256 price,
      uint256 startedAt,
      uint256 timeStamp,
      uint80 answeredInRound
    ) = aggregatorContract.latestRoundData();

    return (roundID, price, startedAt, timeStamp, answeredInRound);
  }

  /**
   * @notice Returns a given round from the reference contract.
   * @param _id of round
   */
  function getRound(uint80 _id)
    public
    view
    returns (
      uint80,
      int256,
      uint256,
      uint256,
      uint80
    )
  {
    (
      uint80 roundID,
      int256 price,
      uint256 startedAt,
      uint256 timeStamp,
      uint80 answeredInRound
    ) = aggregatorContract.getRoundData(_id);

    return (roundID, price, startedAt, timeStamp, answeredInRound);
  }

  /**
   * @notice Returns the last time the Oracle was updated.
   */
  function getLatestTimestamp() public view returns (uint256) {
    (, , , uint256 timeStamp, ) = aggregatorContract.latestRoundData();
    return timeStamp;
  }

  /**
   * @notice Returns a previous answer updated on the Oracle.
   * @param _id of round
   * @return price
   */
  function getPreviousAnswer(uint80 _id) public view returns (int256) {
    (uint80 roundID, int256 price, , , ) = aggregatorContract.getRoundData(_id);
    require(
      _id <= roundID,
      "ChainlinkOracle::getPreviousAnswer: not enough history"
    );
    return price;
  }

  /**
   * @notice Returns a previous time the Oracle was updated.
   * @param _id of round
   * @return timeStamp
   */
  function getPreviousTimestamp(uint80 _id) public view returns (uint256) {
    (uint80 roundID, , , uint256 timeStamp, ) =
      aggregatorContract.getRoundData(_id);
    require(
      _id <= roundID,
      "ChainlinkOracle::getPreviousTimestamp: not enough history"
    );
    return timeStamp;
  }

  /**
   * @notice ERC165 Standard for support of interfaces.
   */
  function supportsInterface(bytes4 interfaceId)
    external
    pure
    override
    returns (bool)
  {
    return (interfaceId == _INTERFACE_ID_CHAINLINK_ORACLE ||
      interfaceId == _INTERFACE_ID_ERC165);
  }
}
