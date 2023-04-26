pragma solidity ^0.4.10;

import '../common/Manageable.sol';
import './IERC20Token.sol';
import './ITokenHolder.sol';

/**@dev A convenient way to manage token's of a contract */
contract TokenHolder is ITokenHolder, Manageable {
    
    function TokenHolder() {
    }

    /** @dev Withdraws tokens held by the contract and sends them to a given address */
    function withdrawTokens(IERC20Token _token, address _to, uint256 _amount)
        public
        managerOnly
    {
        assert(_token.transfer(_to, _amount));
    }
}
