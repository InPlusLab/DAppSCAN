pragma solidity ^0.4.18;

import 'zeppelin-solidity/contracts/token/BasicToken.sol';


/**
 * @title Token which could be burned by any holder.
 */
contract BurnableToken is BasicToken {

    event Burn(address indexed from, uint256 amount);

    /**
     * Function to burn msg.sender's tokens.
     *
     * @param _amount amount of tokens to burn
     *
     * @return boolean that indicates if the operation was successful
     */
    function burn(uint256 _amount)
        public
        returns (bool)
    {
        address from = msg.sender;

        require(_amount > 0);
        require(_amount <= balances[from]);

        totalSupply = totalSupply.sub(_amount);
        balances[from] = balances[from].sub(_amount);
        Burn(from, _amount);
        Transfer(from, address(0), _amount);

        return true;
    }
}
