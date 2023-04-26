// SPDX-License-Identifier: Unlicensed

pragma solidity 0.7.6;

import "../StrategyCommon.sol";

contract Arbitrary is StrategyCommon {

    constructor(address oneTokenFactory_, address oneToken, string memory description) 
        StrategyCommon(oneTokenFactory_, oneToken, description)
    {}


    /**
    @notice Governance can work with collateral and treasury assets. Can swap assets.
           Add assets with oracles to include newly acquired tokens in inventory for reporting/accounting functions.
    @param target address/smart contract you are interacting with
    @param value msg.value (amount of eth in WEI you are sending. Most of the time it is 0)
    @param signature the function signature (name of the function and the types of the arguments)
           for example: "transfer(address,uint256)", or "approve(address,uint256)"
    @param data abi-encodeded byte-code of the parameter values you are sending.
    */
    function executeTransaction(address target, uint value, string memory signature, bytes memory data) public payable onlyOwner returns (bytes memory) {
        bytes memory callData;

        if (bytes(signature).length == 0) {
            callData = data;
        } else {
            callData = abi.encodePacked(bytes4(keccak256(bytes(signature))), data);
        }

        // solium-disable-next-line security/no-call-value
        (bool success, bytes memory returnData) = target.call{ value: value }(callData);
        require(success, "OneTokenV1::executeTransaction: Transaction execution reverted.");
        return returnData;
    }
}
