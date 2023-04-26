pragma solidity ^0.4.10;

/**#@dev interface to contract that contains ether distributed among several receivers */
contract IFund {

    /**@dev Returns how much ether can be claimed */
    function etherBalanceOf(address receiver) public constant returns (uint balance) {receiver;balance;}
    
    /**@dev Withdraws caller's share to it */
    function withdraw(uint amount) public;

    /**@dev Withdraws caller's share to some another address */
    function withdrawTo(address to, uint amount) public;
}