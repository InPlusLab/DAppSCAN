pragma solidity ^0.4.24;
/**
 * @author Nikola Madjarevic
 * Created at 12/25/18
 */
contract IMaintainingPattern {
    function addMaintainers(address [] _maintainers) public;
    function removeMaintainers(address [] _maintainers) public;
}
