pragma solidity ^0.5.16;

contract TemporarilyOwned {
    address public temporaryOwner;
    uint public expiryTime;

    constructor(address _temporaryOwner, uint _ownershipDuration) public {
        require(_temporaryOwner != address(0), "Temp owner address cannot be 0");

        temporaryOwner = _temporaryOwner;
        expiryTime = now + _ownershipDuration;
    }
    // SWC-111-Use of Deprecated Solidity Functions:L14-L17
    modifier onlyTemporaryOwner {
        _onlyTemporaryOwner();
        _;
    }
    // SWC-111-Use of Deprecated Solidity Functions:L19-22
    function _onlyTemporaryOwner() private view {
        require(now < expiryTime, "Ownership expired");
        require(msg.sender == temporaryOwner, "Only executable by temp owner");
    }
}
