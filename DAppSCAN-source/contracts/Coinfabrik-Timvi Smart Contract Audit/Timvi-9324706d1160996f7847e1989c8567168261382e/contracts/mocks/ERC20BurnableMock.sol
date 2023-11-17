pragma solidity 0.5.11;

import "../TimviToken.sol";

contract ERC20BurnableMock is TimviToken {

    constructor(address initialAccount, uint256 initialBalance, address _settings) public TimviToken(_settings) {
        _mint(initialAccount, initialBalance);
    }

}
