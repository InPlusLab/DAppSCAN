// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../../security/DurationGuard.sol";
import "../interfaces/IBondedStrategy.sol";

contract BondedStrategy is DurationGuard, IBondedStrategy {

    address public override stnd;
    uint256 public override totalSupply;
    mapping(address => uint256) public override bonded;
    bytes32 public constant CLAIM_ROLE = keccak256("CLAIM_ROLE");
    bytes32 public constant BOND_ROLE = keccak256("BOND_ROLE");
    
    constructor(
        address stnd_
    ) {
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(ADMIN_ROLE, _msgSender());
        setDuration(BOND_ROLE, 14 days);
        setDuration(CLAIM_ROLE, 14 days);
        stnd = stnd_;
    }

    function claim(address token) external override onlyPerDuration(CLAIM_ROLE, token) returns (bool success) {
        require(token != stnd, "BondedStrategy: Invalid Claim");
        require(block.timestamp - lastTx[_msgSender()][stnd] >= _durations[CLAIM_ROLE]);
        uint256 proRataBonded = bonded[msg.sender] * IERC20(token).balanceOf(address(this)) / totalSupply;
        require(IERC20(token).transfer(msg.sender, proRataBonded), "BondedStrategy: fee transfer failed");
        emit DividendClaimed(msg.sender, token, proRataBonded);
        return true;
    }

    function bond(uint256 amount_) external {
        require(IERC20(stnd).transferFrom(msg.sender, address(this), amount_), "BondedStrategy: Not enough allowance to move with given amount");
        bonded[msg.sender] += amount_;
        totalSupply += amount_;
        lastTx[_msgSender()][stnd] = block.timestamp;
        emit Bonded(msg.sender, amount_);
    }

    function unbond(uint256 amount_) external onlyPerDuration(BOND_ROLE, stnd) {
        require(bonded[msg.sender] >= amount_, "BondedStrategy: Not enough bonded STND");
        require(
            block.timestamp - lastTx[msg.sender][stnd] >= _durations[BOND_ROLE],
            "BondedGuard: A month has not passed from the last bonded tx"
        );
        bonded[msg.sender] -= amount_;
        totalSupply -= amount_;
        IERC20(stnd).transfer(msg.sender, amount_);
        emit UnBonded(msg.sender, amount_);
    }
}