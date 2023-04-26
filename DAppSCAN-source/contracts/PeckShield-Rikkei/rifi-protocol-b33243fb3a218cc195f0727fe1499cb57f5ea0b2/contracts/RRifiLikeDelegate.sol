pragma solidity ^0.5.16;

import "./RBep20Delegate.sol";

interface RifiLike {
  function delegate(address delegatee) external;
}

/**
 * @title Rifi's RRifiLikeDelegate Contract
 * @notice RTokens which can 'delegate votes' of their underlying BEP-20
 * @author Rifi
 */
contract RRifiLikeDelegate is RBep20Delegate {
  /**
   * @notice Construct an empty delegate
   */
  constructor() public RBep20Delegate() {}

  /**
   * @notice Admin call to delegate the votes of the RIFI-like underlying
   * @param rifiLikeDelegatee The address to delegate votes to
   */
  function _delegateRifiLikeTo(address rifiLikeDelegatee) external {
    require(msg.sender == admin, "only the admin may set the rifi-like delegate");
    RifiLike(underlying).delegate(rifiLikeDelegatee);
  }
}
