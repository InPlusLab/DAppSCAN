pragma solidity >=0.5.16;

interface IRewardToken {
    function mint(address _recipient, uint256 _amount) external;
}
