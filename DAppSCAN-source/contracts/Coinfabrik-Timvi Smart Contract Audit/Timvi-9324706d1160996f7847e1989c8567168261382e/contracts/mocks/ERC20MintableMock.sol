pragma solidity 0.5.11;

import "../TimviToken.sol";

contract ERC20MintableMock is TimviToken {
    constructor(address _settings) public TimviToken(_settings) {}
}
