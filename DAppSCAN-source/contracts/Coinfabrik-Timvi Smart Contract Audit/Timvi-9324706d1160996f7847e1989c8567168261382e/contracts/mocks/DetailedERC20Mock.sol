pragma solidity 0.5.11;

import "../TimviToken.sol";

contract ERC20DetailedMock is ERC20Detailed {
    constructor(
        string memory name,
        string memory symbol,
        uint8 decimals
    )
    ERC20Detailed(name, symbol, decimals)
    public
    {}
}
