// SPDX-License-Identifier: Unlicense
pragma solidity 0.5.17;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/ownership/Ownable.sol";

/**
 * @title Staking Contract
 * @notice Contract which allows users to stake their BCUBE tokens to gain access to
 * free services on the website
 * @author Smit Rajput @ b-cube.ai
 **/

contract Staking is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    mapping(address => uint256) public bcubeStakeRegistry;

    IERC20 private bcube;

    event LogEtherReceived(address indexed sender, uint256 weiReceived);
    event LogBcubeStaking(address indexed staker, uint256 bcubeAmount);
    event LogBcubeUnstaking(address indexed unstaker, uint256 bcubeAmount);

    function() external payable {
        emit LogEtherReceived(_msgSender(), msg.value);
    }

    constructor(IERC20 _bcube) public {
        bcube = _bcube;
    }

    function stake(uint256 _bcubeAmount) external {
        require(_bcubeAmount > 0, "Staking non-positive BCUBE");
        bcubeStakeRegistry[_msgSender()] = bcubeStakeRegistry[_msgSender()].add(
            _bcubeAmount
        );
        bcube.safeTransferFrom(_msgSender(), address(this), _bcubeAmount);
        emit LogBcubeStaking(_msgSender(), _bcubeAmount);
    }

    function unstake(uint256 _bcubeAmount) external {
        require(_bcubeAmount > 0, "Unstaking non-positive BCUBE");
        require(
            bcubeStakeRegistry[_msgSender()] >= _bcubeAmount,
            "Insufficient staked bcube"
        );
        bcubeStakeRegistry[_msgSender()] = bcubeStakeRegistry[_msgSender()].sub(
            _bcubeAmount
        );
        bcube.safeTransferFrom(address(this), _msgSender(), _bcubeAmount);
        emit LogBcubeUnstaking(_msgSender(), _bcubeAmount);
    }
}
