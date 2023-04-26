
pragma solidity ^0.4.0;

/*
 * Token - is a smart contract interface 
 * for managing common functionality of 
 * a token.
 *
 * ERC.20 Token standard: https://github.com/eth ereum/EIPs/issues/20
 */
contract TokenInterface {

        
    // total amount of tokens
    uint totalSupply;

    
    /**
     *
     * balanceOf() - constant function check concrete tokens balance  
     *
     *  @param owner - account owner
     *  
     *  @return the value of balance 
     */                               
    function balanceOf(address owner) constant returns (uint256 balance);
    
    function transfer(address to, uint256 value) returns (bool success);

    function transferFrom(address from, address to, uint256 value) returns (bool success);

    /**
     *
     * approve() - function approves to a person to spend some tokens from 
     *           owner balance. 
     *
     *  @param spender - person whom this right been granted.
     *  @param value   - value to spend.
     * 
     *  @return true in case of succes, otherwise failure
     * 
     */
    function approve(address spender, uint256 value) returns (bool success);

    /**
     *
     * allowance() - constant function to check how mouch is 
     *               permited to spend to 3rd person from owner balance
     *
     *  @param owner   - owner of the balance
     *  @param spender - permited to spend from this balance person 
     *  
     *  @return - remaining right to spend 
     * 
     */
    function allowance(address owner, address spender) constant returns (uint256 remaining);

    // events notifications
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}
