pragma solidity 0.5.16;

import "./Permissions.sol";


contract SlashingTable is Permissions {
    mapping (uint => uint) private _penalties;

    function setPenalty(string calldata offense, uint penalty) external onlyOwner {
        _penalties[uint(keccak256(abi.encodePacked(offense)))] = penalty;
    }

    function getPenalty(string calldata offense) external view returns (uint) {
        uint penalty = _penalties[uint(keccak256(abi.encodePacked(offense)))];
        return penalty;
    }

    function initialize(address _contractManager) public initializer {
        Permissions.initialize(_contractManager);
    }
}
