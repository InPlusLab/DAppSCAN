pragma solidity ^0.4.24;

contract IDecentralizedNation {

    function getMembersVotingPoints(
        address _memberAddress
    )
    public
    view
    returns (uint);


    function getMemberid(
        address _member
    )
    public
    view
    returns (uint);
}
