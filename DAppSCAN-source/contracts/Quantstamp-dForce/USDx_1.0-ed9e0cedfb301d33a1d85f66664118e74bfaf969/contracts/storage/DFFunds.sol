pragma solidity ^0.5.2;

import '../token/interfaces/IERC20Token.sol';
import '../utility/DSMath.sol';
import '../utility/DSAuth.sol';
import '../utility/Utils.sol';

contract DFFunds is DSMath, DSAuth, Utils {

    function transferOut(address _tokenID, address _to, uint _amount)
        public
        validAddress(_to)
        auth
        returns (bool)
    {
        uint _balance = IERC20Token(_tokenID).balanceOf(_to);
        IERC20Token(_tokenID).transfer(_to, _amount);
        assert(sub(IERC20Token(_tokenID).balanceOf(_to), _balance) == _amount);
        return true;
    }
}