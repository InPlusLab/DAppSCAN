pragma solidity ^0.5.2;

import '../token/interfaces/IERC20Token.sol';
import '../utility/DSMath.sol';
import '../utility/DSAuth.sol';
import '../utility/Utils.sol';

contract DFPool is DSMath, DSAuth, Utils {

    address dfcol;

    constructor (address _dfcol) public {
        dfcol = _dfcol;
    }

    function transferFromSender(address _tokenID, address _from, uint _amount)
        public
        auth
        returns (bool)
    {
        uint _balance = IERC20Token(_tokenID).balanceOf(address(this));
        IERC20Token(_tokenID).transferFrom(_from, address(this), _amount);
        assert(sub(IERC20Token(_tokenID).balanceOf(address(this)), _balance) == _amount);
        return true;
    }

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

    function transferToCol(address _tokenID, uint _amount)
        public
        auth
        returns (bool)
    {
        require(dfcol != address(0), "TransferToCol: collateral address empty.");
        uint _balance = IERC20Token(_tokenID).balanceOf(dfcol);
        IERC20Token(_tokenID).transfer(dfcol, _amount);
        assert(sub(IERC20Token(_tokenID).balanceOf(dfcol), _balance) == _amount);
        return true;
    }

    function transferFromSenderToCol(address _tokenID, address _from, uint _amount)
        public
        auth
        returns (bool)
    {
        require(dfcol != address(0), "TransferFromSenderToCol: collateral address empty.");
        uint _balance = IERC20Token(_tokenID).balanceOf(dfcol);
        IERC20Token(_tokenID).transferFrom(_from, dfcol, _amount);
        assert(sub(IERC20Token(_tokenID).balanceOf(dfcol), _balance) == _amount);
        return true;
    }

    function approveToEngine(address _tokenIdx, address _engineAddress) public auth {
        IERC20Token(_tokenIdx).approve(_engineAddress, uint(-1));
    }
}
