pragma solidity ^0.4.24;

contract ITwoKeyWeightedVoteContract {
    function getDescription() public view returns(string);
    function transferSig(bytes sig) public returns (address[]);
    function setValid() public;
    function getDynamicData() public view returns (uint,uint,uint,uint,uint,uint);
    function getHowMuchAddressPutPower(address add) public view returns (uint);
    function getVoteAndChoicePerAddress(address voter) public view returns (bool, uint);
    function getAllVoters() public view returns (address[]);
}
