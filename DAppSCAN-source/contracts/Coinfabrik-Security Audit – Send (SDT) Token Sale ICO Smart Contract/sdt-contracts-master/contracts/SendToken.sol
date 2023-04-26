pragma solidity ^0.4.18;

import "./SnapshotToken.sol";
import './ISendToken.sol';
import './IEscrow.sol';
import 'zeppelin-solidity/contracts/token/BurnableToken.sol';


/**
 * @title Send token
 *
 * @dev Implementation of Send Consensus network Standard
 * @dev https://send.sd/token
 */
contract SendToken is ISendToken, SnapshotToken, BurnableToken {
  IEscrow public escrow;

  mapping (address => bool) internal verifiedAddresses;

  modifier verifiedResticted() {
    require(verifiedAddresses[msg.sender]);
    _;
  }

  modifier escrowResticted() {
    require(msg.sender == address(escrow));
    _;
  }

  /**
   * @dev Check if an address is whitelisted by SEND
   * @param _address Address to check
   * @return bool
   */
  function isVerified(address _address) public view returns(bool) {
    return verifiedAddresses[_address];
  }

  /**
   * @dev Verify an addres
   * @notice Only contract owner
   * @param _address Address to verify
   */
  function verify(address _address) public onlyOwner {
    verifiedAddresses[_address] = true;
  }

  /**
   * @dev Remove Verified status of a given address
   * @notice Only contract owner
   * @param _address Address to unverify
   */
  function unverify(address _address) public onlyOwner {
    verifiedAddresses[_address] = false;
  }

  /**
   * @dev Remove Verified status of a given address
   * @notice Only contract owner
   * @param _address Address to unverify
   */
  function setEscrow(address _address) public onlyOwner {
    escrow = IEscrow(_address);
  }

  /**
   * @dev Transfer from one address to another issuing ane xchange rate
   * @notice Only verified addresses
   * @notice Exchange rate has 18 decimal places
   * @notice Value + fee <= allowance
   * @param _from address The address which you want to send tokens from
   * @param _to address The address which you want to transfer to
   * @param _value uint256 the amount of tokens to be transferred
   * @param _referenceId internal app/user ID
   * @param _exchangeRate Exchange rate to sign transaction
   * @param _fee fee tot ake from sender
   */
  function verifiedTransferFrom(
      address _from,
      address _to,
      uint256 _value,
      uint256 _referenceId,
      uint256 _exchangeRate,
      uint256 _fee
  ) public verifiedResticted {
    require(_exchangeRate > 0);

    transferFrom(_from, _to, _value);
    transferFrom(_from, msg.sender, _fee);

    VerifiedTransfer(
      _from,
      _to,
      msg.sender,
      _value,
      _referenceId,
      _exchangeRate
    );
  }

  /**
   * @dev create an escrow transfer being the arbitrator
   * @param _sender Address to send tokens
   * @param _recipient Address to receive tokens
   * @param _transactionId internal ID for arbitrator
   * @param _tokens Amount of tokens to lock
   * @param _fee A fee to be paid to arbitrator (may be 0)
   * @param _expiration After this timestamp, user can claim tokens back.
   */
  function createEscrow(
      address _sender,
      address _recipient,
      uint256 _transactionId,
      uint256 _tokens,
      uint256 _fee,
      uint256 _expiration
  ) public {
    escrow.create(
      _sender,
      _recipient,
      msg.sender,
      _transactionId,
      _tokens,
      _fee,
      _expiration
    );
  }

  /**
   * @dev fund escrow
   * @dev specified amount will be locked on escrow contract
   * @param _arbitrator Address of escrow arbitrator
   * @param _transactionId internal ID for arbitrator
   * @param _tokens Amount of tokens to lock
   * @param _fee A fee to be paid to arbitrator (may be 0)
   */
  function fundEscrow(
      address _arbitrator,
      uint256 _transactionId,
      uint256 _tokens,
      uint256 _fee
  ) public {
    uint256 total = _tokens.add(_fee);
    transfer(escrow, total);

    escrow.fund(
      msg.sender,
      _arbitrator,
      _transactionId,
      _tokens,
      _fee
    );
  }

  /**
   * @dev Issue exchange rates from escrow contract
   * @param _from Address to send tokens
   * @param _to Address to receive tokens
   * @param _verifiedAddress Address issuing the exchange rate
   * @param _value amount
   * @param _transactionId internal ID for issuer's reference
   * @param _exchangeRate exchange rate
   */
  function issueExchangeRate(
      address _from,
      address _to,
      address _verifiedAddress,
      uint256 _value,
      uint256 _transactionId,
      uint256 _exchangeRate
  ) public escrowResticted {
    bool noRate = (_exchangeRate == 0);
    if (isVerified(_verifiedAddress)) {
      require(!noRate);
      VerifiedTransfer(
        _from,
        _to,
        _verifiedAddress,
        _value,
        _transactionId,
        _exchangeRate
      );
    } else {
      require(noRate);
    }
  }
}
