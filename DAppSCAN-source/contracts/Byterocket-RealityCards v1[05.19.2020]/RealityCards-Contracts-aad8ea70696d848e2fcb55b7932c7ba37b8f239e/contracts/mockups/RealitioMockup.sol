pragma solidity 0.5.13;

// this is only for ganache testing. Public chain deployments will use the existing Realitio contracts. 

contract RealitioMockup

{
    uint result = 420;

    function setResult(uint _result) public
    {
        if (_result == 69) {
            result = ((2**256)-1);
        } else {
            result = _result;
        }
    }

    function askQuestion(uint256 template_id, string calldata question, address arbitrator, uint32 timeout, uint32 opening_ts, uint256 nonce) external payable returns (bytes32) {
        // to get rid of compiler warnings:
        template_id;
        nonce;
        question;
        arbitrator;
        timeout;
        opening_ts;
        return 0x8d293509129e26299990826db10c48241be5f59f2e4f61c0c9d550e4451e1a38;
    }

    // 420 = not resolved
    // 69 = invalid
    function resultFor(bytes32 question_id) external view returns (bytes32) {
        require(result != 420);
        require(question_id == 0x8d293509129e26299990826db10c48241be5f59f2e4f61c0c9d550e4451e1a38);
        return bytes32(result);
    }

    function isFinalized(bytes32 question_id) external view returns (bool) {
        require(question_id == 0x8d293509129e26299990826db10c48241be5f59f2e4f61c0c9d550e4451e1a38);
        if (result == 420) {
            return false;
        } else {
            return true;
        }

    } 

}

