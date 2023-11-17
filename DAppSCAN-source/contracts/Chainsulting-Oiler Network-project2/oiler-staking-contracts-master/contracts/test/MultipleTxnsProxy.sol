pragma solidity 0.8.3;

contract MultipleTxnsProxy {
    function multipleExecution(bytes[] calldata txnsData, address[] calldata targets) external {
        for(uint i = 0 ; i < txnsData.length; i++) {
            (bool success, ) = targets[i].call(txnsData[i]);
            require(success);
        }
    }
}