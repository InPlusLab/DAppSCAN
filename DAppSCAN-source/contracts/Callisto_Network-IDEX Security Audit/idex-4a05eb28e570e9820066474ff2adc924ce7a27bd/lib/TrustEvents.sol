pragma solidity ^0.4.6;
contract TrustEvents {
  event AuthInit(address indexed from);
  event AuthComplete(address indexed from, address indexed with);
  event AuthPending(address indexed from);
  event Unauthorized(address indexed from);
  event InitCancel(address indexed from);
  event NothingToCancel(address indexed from);
  event SetMasterKey(address indexed from);
  event AuthCancel(address indexed from, address indexed with);
}
