pragma solidity ^0.4.18;


/**
 * @title Escrow interface
 *
 * @dev https://send.sd/token
 */
interface IEscrow {

  event Created(
    address indexed sender,
    address indexed recipient,
    address indexed arbitrator,
    uint256 transactionId
  );
  event Released(address indexed arbitrator, address indexed sentTo, uint256 transactionId);
  event Dispute(address indexed arbitrator, uint256 transactionId);
  event Paid(address indexed arbitrator, uint256 transactionId);

  function create(
      address _sender,
      address _recipient,
      address _arbitrator,
      uint256 _transactionId,
      uint256 _tokens,
      uint256 _fee,
      uint256 _expiration
  ) public;

  function fund(
      address _sender,
      address _arbitrator,
      uint256 _transactionId,
      uint256 _tokens,
      uint256 _fee
  ) public;

}
