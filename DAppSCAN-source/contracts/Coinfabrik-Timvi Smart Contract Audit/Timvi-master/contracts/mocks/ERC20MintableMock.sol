pragma solidity 0.4.25;

import "../TimviToken.sol";

contract ERC20MintableMock is TimviToken {
    constructor(address _settings) public TimviToken(_settings) {}
}
