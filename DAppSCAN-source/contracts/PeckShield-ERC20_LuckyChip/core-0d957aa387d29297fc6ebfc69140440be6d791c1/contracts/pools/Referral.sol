// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../interfaces/IBEP20.sol";
import "../interfaces/IReferral.sol";
import "../interfaces/ILuckyPower.sol";
import "../libraries/SafeBEP20.sol";

contract Referral is IReferral, Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;
    using EnumerableSet for EnumerableSet.AddressSet;
   
    EnumerableSet.AddressSet private _operators; 
    IBEP20 public lcToken;
    ILuckyPower public luckyPower;

    struct ReferrerInfo{
        uint256 lpCommission;
        uint256 betCommission;
        uint256 rankCommission;
        uint256 pendingLpCommission;
        uint256 pendingBetCommission;
        uint256 pendingRankCommission;
    }

    mapping(address => address) public referrers; // user address => referrer address
    mapping(address => uint256) public referralsCount; // referrer address => referrals count
    mapping(address => ReferrerInfo) public referrerInfo; // referrer address => Referrer Info

    event ReferrerRecorded(address indexed user, address indexed referrer);
    event LpCommissionRecorded(address indexed referrer, uint256 commission);
    event BetCommissionRecorded(address indexed referrer, uint256 commission);
    event RankCommissionRecorded(address indexed referrer, uint256 commission);
    event ClaimLpCommission(address indexed referrer, uint256 amount);
    event ClaimBetCommission(address indexed referrer, uint256 amount);
    event ClaimRankCommission(address indexed referrer, uint256 amount);
    event SetLuckyPower(address indexed _luckyPowerAddr);


    constructor(address _lcTokenAddr) public {
        lcToken = IBEP20(_lcTokenAddr);
    }

    function isOperator(address account) public view returns (bool) {
        return EnumerableSet.contains(_operators, account);
    }

    // modifier for operator
    modifier onlyOperator() {
        require(isOperator(msg.sender), "caller is not a operator");
        _;
    }

    function addOperator(address _addOperator) public onlyOwner returns (bool) {
        require(_addOperator != address(0), "Token: _addOperator is the zero address");
        return EnumerableSet.add(_operators, _addOperator);
    }

    function delOperator(address _delOperator) public onlyOwner returns (bool) {
        require(_delOperator != address(0), "Token: _delOperator is the zero address");
        return EnumerableSet.remove(_operators, _delOperator);
    }

    function recordReferrer(address _user, address _referrer) public override onlyOperator {
        if (_user != address(0)
            && _referrer != address(0)
            && _user != _referrer
            && referrers[_user] == address(0)
        ) {
            referrers[_user] = _referrer;
            referralsCount[_referrer] = referralsCount[_referrer].add(1);
            emit ReferrerRecorded(_user, _referrer);
        }
    }

    function recordLpCommission(address _referrer, uint256 _commission) public override onlyOperator {
        if (_referrer != address(0) && _commission > 0) {
            ReferrerInfo storage info = referrerInfo[_referrer];
            info.lpCommission = info.lpCommission.add(_commission);
            info.pendingLpCommission = info.pendingLpCommission.add(_commission);

            emit LpCommissionRecorded(_referrer, _commission);
        }
    }

    function recordBetCommission(address _referrer, uint256 _commission) public override onlyOperator {
        if (_referrer != address(0) && _commission > 0) {
            ReferrerInfo storage info = referrerInfo[_referrer];
            info.betCommission = info.betCommission.add(_commission);
            info.pendingBetCommission = info.pendingBetCommission.add(_commission);
            
            emit BetCommissionRecorded(_referrer, _commission);
        }
    }

    function recordRankCommission(address _referrer, uint256 _commission) public override onlyOperator {
        if (_referrer != address(0) && _commission > 0) {
            ReferrerInfo storage info = referrerInfo[_referrer];
            info.rankCommission = info.rankCommission.add(_commission);
            info.pendingRankCommission = info.pendingRankCommission.add(_commission);
            
            emit RankCommissionRecorded(_referrer, _commission);
        }
    }

    // Get the referrer address that referred the user
    function getReferrer(address _user) public override view returns (address) {
        return referrers[_user];
    }

    function getReferralCommission(address _referrer) public override view returns(uint256, uint256, uint256, uint256, uint256, uint256){
        ReferrerInfo storage info = referrerInfo[_referrer];
        return (info.lpCommission, info.betCommission, info.rankCommission, info.pendingLpCommission, info.pendingBetCommission, info.pendingRankCommission);
    }

    function getLuckyPower(address _referrer) public override view returns (uint256){
        ReferrerInfo storage info = referrerInfo[_referrer];
        return info.pendingLpCommission.add(info.pendingBetCommission).add(info.pendingRankCommission);
    }

    function claimLpCommission() public override nonReentrant {
        address referrer = msg.sender;
        ReferrerInfo storage info = referrerInfo[referrer];
        if(info.pendingLpCommission > 0){
            uint256 tmpAmount = info.pendingLpCommission;
            info.pendingLpCommission = 0;
            lcToken.safeTransfer(referrer, tmpAmount);
            if(address(luckyPower) != address(0)){
                luckyPower.updatePower(referrer);
            }
            emit ClaimLpCommission(referrer, tmpAmount);
        }
    }

    function claimBetCommission() public override nonReentrant {
        address referrer = msg.sender;
        ReferrerInfo storage info = referrerInfo[referrer];
        if(info.pendingBetCommission > 0){
            uint256 tmpAmount = info.pendingBetCommission;
            info.pendingBetCommission = 0;
            lcToken.safeTransfer(referrer, tmpAmount);
            if(address(luckyPower) != address(0)){
                luckyPower.updatePower(referrer);
            }
            emit ClaimBetCommission(referrer, tmpAmount);
        }
    }

    function claimRankCommission() public override nonReentrant {
        address referrer = msg.sender;
        ReferrerInfo storage info = referrerInfo[referrer];
        if(info.pendingRankCommission > 0){
            uint256 tmpAmount = info.pendingRankCommission;
            info.pendingRankCommission = 0;
            lcToken.safeTransfer(referrer, tmpAmount);
            if(address(luckyPower) != address(0)){
                luckyPower.updatePower(referrer);
            }
            emit ClaimRankCommission(referrer, tmpAmount);
        }
    }

    function setLuckyPower(address _luckyPowerAddr) public onlyOwner {
        require(_luckyPowerAddr != address(0), "Zero");
        luckyPower = ILuckyPower(_luckyPowerAddr);
        emit SetLuckyPower(_luckyPowerAddr);
    }
}
