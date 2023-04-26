pragma solidity ^0.5.2;

import '../update/DFUpgrader.sol';

contract DFProtocol is DFUpgrader {
    event Deposit (address indexed _tokenID, address indexed _sender, uint _tokenAmount, uint _usdxAmount);
    event Withdraw(address indexed _tokenID, address indexed _sender, uint _expectedAmount, uint _actualAmount);
    event Destroy (address indexed _sender, uint _usdxAmount);
    event Claim(address indexed _sender, uint _usdxAmount);
    event OneClickMinting(address indexed _sender, uint _usdxAmount);

    function deposit(address _tokenID, uint _feeTokenIdx, uint _tokenAmount) public returns (uint){
        uint _usdxAmount = iDFEngine.deposit(msg.sender, _tokenID, _feeTokenIdx, _tokenAmount);
        emit Deposit(_tokenID, msg.sender, _tokenAmount, _usdxAmount);
        return _usdxAmount;
    }

    function withdraw(address _tokenID, uint _feeTokenIdx, uint _expectedAmount) public returns (uint) {
        uint _actualAmount = iDFEngine.withdraw(msg.sender, _tokenID, _feeTokenIdx, _expectedAmount);
        emit Withdraw(_tokenID, msg.sender, _expectedAmount, _actualAmount);
        return _actualAmount;
    }

    function destroy(uint _feeTokenIdx, uint _usdxAmount) public {
        iDFEngine.destroy(msg.sender, _feeTokenIdx, _usdxAmount);
        emit Destroy(msg.sender, _usdxAmount);
    }

    function claim(uint _feeTokenIdx) public returns (uint) {
        uint _usdxAmount = iDFEngine.claim(msg.sender, _feeTokenIdx);
        emit Claim(msg.sender, _usdxAmount);
        return _usdxAmount;
    }

    function oneClickMinting(uint _feeTokenIdx, uint _usdxAmount) public {
        iDFEngine.oneClickMinting(msg.sender, _feeTokenIdx, _usdxAmount);
        emit OneClickMinting(msg.sender, _usdxAmount);
    }
}
