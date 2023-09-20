// SWC-135-Code With No Effects: L2 - L45
pragma solidity ^0.4.18;


/**
 * @title ISendToken - Send Consensus Network Token interface
 * @dev token interface built on top of ERC20 standard interface
 * @dev see https://send.sd/token
 */
interface ISendToken {
  function transfer(address to, uint256 value) public returns (bool);

  function isVerified(address _address) public constant returns(bool);

  function verify(address _address) public;

  function unverify(address _address) public;

  function verifiedTransferFrom(
      address from,
      address to,
      uint256 value,
      uint256 referenceId,
      uint256 exchangeRate,
      uint256 fee
  ) public;

  function issueExchangeRate(
      address _from,
      address _to,
      address _verifiedAddress,
      uint256 _value,
      uint256 _referenceId,
      uint256 _exchangeRate
  ) public;

  event VerifiedTransfer(
      address indexed from,
      address indexed to,
      address indexed verifiedAddress,
      uint256 value,
      uint256 referenceId,
      uint256 exchangeRate
  );
}
