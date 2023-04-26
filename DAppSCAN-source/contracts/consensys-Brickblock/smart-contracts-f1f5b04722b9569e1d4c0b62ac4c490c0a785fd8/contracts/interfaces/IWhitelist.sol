pragma solidity 0.4.23;

interface IWhitelist {
  function whitelisted(address _address)
    external
    returns (bool);
}