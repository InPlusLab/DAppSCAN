pragma solidity 0.4.25;

import "../TimviToken.sol";

contract ERC20BurnableMock is TimviToken {

    constructor(address initialAccount, uint256 initialBalance, address _settings) public TimviToken(_settings) {
        _mint(initialAccount, initialBalance);
    }

}
