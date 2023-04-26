// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "../../interfaces/Types.sol";

contract LidoMock is ERC20 {
    address private owner;

    event NewStake(uint64, uint256);

    constructor() ERC20("KSM liquid token", "stKSM") {
        owner = msg.sender;
    }

    modifier notImplemented() {
        revert("NOT_IMPLEMENTED");
        _;
    }

    function getStashAccounts() public view returns(Types.Stash[] memory){
        Types.Stash[] memory stake = new Types.Stash[](2);
        // Ferdie DE14BzQ1bDXWPKeLoAqdLAm1GpyAWaWF1knF74cEZeomTBM
        stake[0].stashAccount = 0x1cbd2d43530a44705ad088af313e18f80b53ef16b36177cd4b77b846f2a5f07c;
        // Charlie Fr4NzY1udSFFLzb2R3qxVQkwz9cZraWkyfH4h3mVVk7BK7P
        stake[1].stashAccount = 0x90b5ab205c6974c9ea841be688864633dc9ca8a357843eeacf2314649965fe22;
        return stake;
    }

    function deposit(uint256 amount) external notImplemented{

    }

    function redeem(uint256 amount) external notImplemented{

    }

    function getUnbonded(address holder) external returns (uint256) {
        return 0;
    }

    function claimUnbonded() external notImplemented{

    }

    function getCurrentAPY() external view returns (uint256){
        return 540;
    }

    function setQuorum(uint8 _quorum) external notImplemented{

    }

    function clearReporting() external notImplemented{

    }

    function findLedger(bytes32 _stashAccount) external view notImplemented returns (address){

    }

    function getMinStashBalance() external view returns (uint128){
        return 0;
    }

    function getOracle() external view returns (address){
        return address(0);
    }

    function distributeRewards(uint128 _totalRewards) external {
        _mint(address(this), _totalRewards);
    }
}
