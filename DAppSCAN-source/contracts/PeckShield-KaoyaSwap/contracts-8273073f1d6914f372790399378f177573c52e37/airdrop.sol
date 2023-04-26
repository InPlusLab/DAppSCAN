pragma solidity ^0.8.7;
import 'https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol';

interface IERC20 {

    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function transfer(address recipient, uint256 amount) external returns (bool);

    function allowance(address owner, address spender) external view returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);

}
    struct UserInfo {
        uint256 amount;     // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        uint256 depositTime;
    }
interface IStaking {
    function getUserInfo(address user) external returns(UserInfo memory result);
    function clearUserDepositTime(address user) external;
}

contract airdrop is Ownable{
    address public poolAddress  = 0xb9f72a39AB304D5E6a6f1ADCcA4A11Ff3C330350;
    
    uint period = 86400 * 30;
    function getAirdrop() external {
        UserInfo memory userInfo = IStaking(poolAddress).getUserInfo(msg.sender);
        require(userInfo.depositTime>0,"error");
        uint diff = block.timestamp - userInfo.depositTime;
        IStaking(poolAddress).clearUserDepositTime(msg.sender);
        if(diff>period)
            _sendAirdrop(payable(msg.sender));
    }
    function _sendAirdrop(address payable user) internal{
        user.transfer(10*1e18);
    }
    function setPoolAddress(address _pool) external onlyOwner{
        poolAddress = _pool;
    }
    function setPeriod(uint _period) external onlyOwner{
        period = _period;
    }

    function checkAirdrop(uint depositTime) public view returns (bool) {
        uint diff = block.timestamp - depositTime;
        return diff>period;
    }
}