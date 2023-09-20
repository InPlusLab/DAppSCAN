// contracts/LockletPrivateSale.sol
// SPDX-License-Identifier: No License
// SWC-103-Floating Pragma: L4
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract LockletPrivateSale is Ownable, Pausable {
    using SafeMath for uint256;

    ERC20 private _lktToken;
    mapping(address => uint256) private _investments;

    uint256 public _raisedEth;
    uint256 public _soldedLkt;

    uint256 public _lktPerEth;
    uint256 public _maxEthPerAddr;

    bool private _claimable = false;

    event NewAllowance(uint256 ethCostAmount, uint256 lktPerEth, uint256 lktAllocatedAmount);

    constructor(
        address lktTokenAddr,
        uint256 lktPerEth,
        uint256 maxEthPerAddr
    ) {
        _lktToken = ERC20(lktTokenAddr);
        _lktPerEth = lktPerEth;
        _maxEthPerAddr = maxEthPerAddr;

        _raisedEth = 0;
        _soldedLkt = 0;

        _pause();
    }

    // #region Public

    receive() external payable whenNotPaused {
        uint256 totalEthInvested = _investments[msg.sender].add(msg.value);
        require(totalEthInvested <= _maxEthPerAddr, "LockletPrivateSale: You exceed the Ether limit per wallet");
        _allocateLkt(msg.value);
    }

    function claim() external {
        require(_claimable == true, "LockletPrivateSale: Claim is not activated");

        uint256 lktAmount = getAllowanceByAddr(msg.sender);
        require(lktAmount > 0, "LockletPrivateSale: Nothing to claim");

        require(_lktToken.balanceOf(address(this)) >= lktAmount, "LockletPrivateSale: Not enough LKT available");

        _investments[msg.sender] = 0;
        _lktToken.transfer(msg.sender, lktAmount);
    }

    // #endregion

    // #region Internal

    function _allocateLkt(uint256 ethAmount) private {
        uint256 lktAmount = (ethAmount.mul(_lktPerEth)).div(10**18);
        require(_lktToken.balanceOf(address(this)) >= lktAmount.add(_soldedLkt), "LockletPrivateSale: Not enough LKT available");

        _raisedEth += ethAmount;
        _soldedLkt += lktAmount;
        _investments[msg.sender] += ethAmount;

        emit NewAllowance(ethAmount, _lktPerEth, lktAmount);
    }

    // #endregion

    // #region OnlyOwner

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function setLktPerEth(uint256 lktPerEth) public onlyOwner {
        _lktPerEth = lktPerEth;
    }

    function setMaxEthPerAddr(uint256 maxEthPerAddr) public onlyOwner {
        _maxEthPerAddr = maxEthPerAddr;
    }

    function setClaimable(bool value) public onlyOwner {
        _claimable = value;
    }

    function withdrawEth() public onlyOwner {
        payable(msg.sender).transfer(address(this).balance);
    }

    function withdrawLkt() public onlyOwner {
        _lktToken.transfer(msg.sender, _lktToken.balanceOf(address(this)));
    }

    // #endregion

    // #region Getters

    function getRaisedEth() public view returns (uint256) {
        return _raisedEth;
    }

    function getSoldedLkt() public view returns (uint256) {
        return _soldedLkt;
    }

    function getLktPerEth() public view returns (uint256) {
        return _lktPerEth;
    }

    function getMaxEthPerAddr() public view returns (uint256) {
        return _maxEthPerAddr;
    }

    function getAllowanceByAddr(address addr) public view returns (uint256) {
        uint256 totalEthInvested = _investments[addr];
        uint256 lktAmount = (totalEthInvested.mul(_lktPerEth)).div(10**18);
        return lktAmount;
    }

    function getClaimable() public view returns (bool) {
        return _claimable;
    }

    // #endregion
}
