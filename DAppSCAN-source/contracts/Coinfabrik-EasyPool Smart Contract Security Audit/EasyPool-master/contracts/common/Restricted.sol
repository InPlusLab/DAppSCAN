pragma solidity ^0.4.24;

import "../zeppelin/Ownable.sol";


/**
 * @title Restricted 
 */
contract Restricted is Ownable {  

    address[] public operators;
    mapping(address => bool) public permissions;    

    /**
     * @dev Only operator access.
     */
    modifier onlyOperator() {
        require(permissions[msg.sender]);
        _;
    }

    /**
    * @dev Add new operator address.
    */
    function addOperator(address operator) external onlyOwner {        
        require(operator != address(0));
        require(!permissions[operator]);

        operators.push(operator);
        permissions[operator] = true;
        emit OperatorAdded(operator);
    }

    /**
    * @dev Remove specified operator address.
    */
    function removeOperator(address operator) external onlyOwner {        
        require(operator != address(0));
        require(permissions[operator]);

        uint deleteIndex;
        uint lastIndex = operators.length - 1;
        for (uint i = 0; i <= lastIndex; i++) {
            if(operators[i] == operator) {
                deleteIndex = i;
                break;
            }
        }
        
        if (deleteIndex < lastIndex) {
            operators[deleteIndex] = operators[lastIndex];             
        }

        delete operators[lastIndex];
        operators.length--;              

        permissions[operator] = false;        
        emit OperatorRemoved(operator);
    }

    /**
     * @dev Returns list of all operators.
     */
    function getOperators() public view returns(address[]) {
        return operators;
    }

    event OperatorAdded(address operator);
    event OperatorRemoved(address operator);      
}

