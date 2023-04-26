pragma solidity 0.7.5;

import "../interfaces/IBurnableMintableERC677Token.sol";

/**
 * @title SafeMint
 * @dev Wrapper around the mint() function in all mintable tokens that verifies the return value.
 */
library SafeMint {
    /**
     * @dev Wrapper around IBurnableMintableERC677Token.mint() that verifies that output value is true.
     * @param _token token contract.
     * @param _to address of the tokens receiver.
     * @param _value amount of tokens to mint.
     */
    function safeMint(
        IBurnableMintableERC677Token _token,
        address _to,
        uint256 _value
    ) internal {
        require(_token.mint(_to, _value));
    }
}
