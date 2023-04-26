// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "./libs/SafeMath.sol";
import "./libs/Ownable.sol";

import "./interfaces/IMasterBonus.sol";
import "./interfaces/IBonusAggregator.sol";

/*
The purpose of this contract is to allow us adding bonus to user's reward by adding NFT contracts for example
without updating the masterChef
The owner of this contract will be transferred to a timelock
*/
contract ShibaBonusAggregator is Ownable, IBonusAggregator{
    using SafeMath for uint256;

    IMasterBonus master;

    // pid => address => bonus percent
    mapping(uint256 => mapping(address => uint256)) public userBonusOnFarms;

    mapping (address => bool) public contractBonusSource;

    /**
     * @dev Throws if called by any account other than the verified contracts.
     * Can be an NFT contract for example
     */
    modifier onlyVerifiedContract() {
        require(contractBonusSource[msg.sender], "caller is not in contract list");
        _;
    }
    
    function setupMaster(IMasterBonus _master) external onlyOwner{
        master = _master;
    }

    function addOrRemoveContractBonusSource(address _contract, bool _add) external onlyOwner{
        contractBonusSource[_contract] = _add;
    }

    function addUserBonusOnFarm(address _user, uint256 _percent, uint256 _pid) external onlyVerifiedContract{
        userBonusOnFarms[_pid][_user] = userBonusOnFarms[_pid][_user].add(_percent);
        require(userBonusOnFarms[_pid][_user] < 10000, "Invalid percent");
        master.updateUserBonus(_user, _pid, userBonusOnFarms[_pid][_user]);
    }

    function removeUserBonusOnFarm(address _user, uint256 _percent, uint256 _pid) external onlyVerifiedContract{
        userBonusOnFarms[_pid][_user] = userBonusOnFarms[_pid][_user].sub(_percent);
        master.updateUserBonus(_user, _pid, userBonusOnFarms[_pid][_user]);
    }

    function getBonusOnFarmsForUser(address _user, uint256 _pid) external virtual override view returns (uint256){
        return userBonusOnFarms[_pid][_user];
    }

}
