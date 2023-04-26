pragma solidity ^0.5.2;
pragma experimental ABIEncoderV2; // to enable structure-type parameter

import "../perpetual/Collateral.sol";


contract TestCollateral is Collateral {
    constructor(address _collateral, uint256 decimals) public Collateral(_collateral, decimals) {}

    function depositPublic(uint256 amount) public {
        deposit(msg.sender, amount);
    }

    function depositEtherPublic() public payable {
        deposit(msg.sender, msg.value);
    }

    function applyForWithdrawalPublic(uint256 amount, uint256 delay) public {
        applyForWithdrawal(msg.sender, amount, delay);
    }

    function withdrawPublic(uint256 amount) public {
        withdraw(msg.sender, amount, false);
    }

    function withdrawAllPublic() public {
        withdrawAll(msg.sender);
    }

    function updateBalancePublic(int256 amount) public {
        updateBalance(msg.sender, amount);
    }

    function ensurePositiveBalancePublic() public returns (uint256 loss) {
        return ensurePositiveBalance(msg.sender);
    }

    function transferBalancePublic(address from, address to, uint256 amount) public {
        transferBalance(from, to, amount.toInt256());
    }

    function depositToProtocolPublic(address guy, uint256 rawAmount) public returns (int256) {
        return depositToProtocol(guy, rawAmount);
    }

    function withdrawFromProtocolPublic(address payable guy, uint256 rawAmount) public returns (int256) {
        return withdrawFromProtocol(guy, rawAmount);
    }
}
