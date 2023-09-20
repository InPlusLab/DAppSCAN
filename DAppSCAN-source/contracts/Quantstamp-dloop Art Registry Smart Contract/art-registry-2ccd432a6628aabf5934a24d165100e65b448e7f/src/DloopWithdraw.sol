pragma solidity 0.5.17;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "./DloopManagedToken.sol";

contract DloopWithdraw is DloopManagedToken {
    uint256 private _lastWithdrawal = block.timestamp;
    uint256 private _withdrawalWaitTime = 300;

    event TokenWithdrawn(
        address indexed from,
        address indexed to,
        uint256 indexed tokenId
    );

    event WithdrawalWaitTimeSet(uint256 withdrawalWaitTime);
    event ManagedTransfer(
        address by,
        address indexed from,
        address indexed to,
        uint256 indexed tokenId
    );

    function managedTransfer(address to, uint256 tokenId)
        public
        onlyMinter
        returns (bool)
    {
        require(
            isManaged(tokenId),
            "specified tokenId does not reference a managed token"
        );

        address from = ownerOf(tokenId);
        super._safeTransferFrom(from, to, tokenId, "");
        emit ManagedTransfer(msg.sender, from, to, tokenId);
        return true;
    }

    function withdraw(address to, uint256 tokenId)
        public
        onlyMinter
        returns (bool)
    {
        require(
            isManaged(tokenId),
            "specified tokenId does not reference a managed token"
        );
        require(canWithdrawNow(), "withdrawal is currently locked");

        _lastWithdrawal = block.timestamp;
        super._setManaged(tokenId, false);

        address from = ownerOf(tokenId);
        super._safeTransferFrom(from, to, tokenId, "");

        emit TokenWithdrawn(from, to, tokenId);
        return true;
    }

    function setWithdrawalWaitTime(uint256 withdrawalWaitTime)
        public
        onlyAdmin
        returns (uint256)
    {
        _withdrawalWaitTime = withdrawalWaitTime;
        emit WithdrawalWaitTimeSet(withdrawalWaitTime);
    }

    function getWithdrawalWaitTime() public view returns (uint256) {
        return _withdrawalWaitTime;
    }

    function canWithdrawNow() public view returns (bool) {
        if (_withdrawalWaitTime == 0) {
            return true;
        } else {
            uint256 nextWithdraw = SafeMath.add(
                _lastWithdrawal,
                _withdrawalWaitTime
            );
            // SWC-116-Block values as a proxy for time: L83
            return nextWithdraw <= block.timestamp;
        }
    }

    function getLastWithdrawal() public view returns (uint256) {
        return _lastWithdrawal;
    }

}
