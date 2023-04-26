pragma solidity ^0.4.24;

import "zos-lib/contracts/Initializable.sol";
import "openzeppelin-eth/contracts/token/ERC20/ERC20.sol";

/**
 * @title Props Sidechain Compatible
 * @dev Added a settle function and events
 **/
contract PropsSidechainCompatible is ERC20 {
    event TransferDetails(
        address from,
        uint256 fromBalance,
        address to,
        uint256 toBalance,
        uint256 amount
    );
    
    event Settlement(
        uint256 timestamp,
        address from, 
        address recipient,
        uint256 amount
    );
    
    function transfer(
        address to,
        uint256 value
    )
    public    
    returns (bool)
    {
        if (super.transfer(to, value)) {
            emit TransferDetails(msg.sender, super.balanceOf(msg.sender), to, super.balanceOf(to), value);
            return true;
        }
        return false;
    }

    function transferFrom(
    address from,
    address to,
    uint256 value
    )
    public    
    returns (bool)
    {
        if (super.transferFrom(from, to, value)) {
            emit TransferDetails(from, super.balanceOf(from), to, super.balanceOf(to), value);
            return true;
        }
        return false;    
  }
    /**
    * @notice settle pending earnings on the PROPS-Chain by using this settlement method to transfer and emit a settlement Event
    * @param to The address to transfer to.
    * @param value The amount to be transferred.
    */
    function settle(
        address to,
        uint256 value
    ) public returns (bool)
    {
        if (super.transfer(to, value)) {
            emit TransferDetails(msg.sender, super.balanceOf(msg.sender), to, super.balanceOf(to), value);
            emit Settlement(block.timestamp, msg.sender, to, value);            
            return true;
        } 
        return false;
    }  
}
