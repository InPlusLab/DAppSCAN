pragma solidity ^0.4.24;

contract ITwoKeyMaintainersRegistry {
    function onlyMaintainer(address _sender) public view returns (bool);
}
