pragma solidity ^0.4.24;
/**
 * @author Nikola Madjarevic
 * Created at 2/1/19
 */
contract ITwoKeyAcquisitionARC {
    function getReceivedFrom(address _receiver) public view returns (address);
    function balanceOf(address _owner) public view returns (uint256);
}
