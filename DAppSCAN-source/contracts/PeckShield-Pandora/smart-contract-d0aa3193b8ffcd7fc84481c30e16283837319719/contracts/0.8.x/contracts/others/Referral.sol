//SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../interfaces/IPAN.sol";
import "../interfaces/IMinter.sol";


contract Referral is Ownable {
    address public operator;
    uint256 public lastUpdateBlock;
    uint256 public PANPerBlock;
    IPAN public PAN;
    IMinter public minter;


    modifier onlyOperator() {
        require(msg.sender == operator, 'Referral: caller is not operator');
        _;
    }

    constructor(address _PAN, uint256 _PANPerBlock, IMinter _minter) {
        PAN = IPAN(_PAN);
        PANPerBlock = _PANPerBlock;
        operator = msg.sender;
        lastUpdateBlock = block.number;
        minter = _minter;
    }

    function mintReward() public {
        uint256 _amount = (block.number - lastUpdateBlock) * PANPerBlock;
        minter.transfer(address(this), _amount);
        lastUpdateBlock = block.number;
    }

    function distribute(address[] memory _accounts, uint256[] memory _amounts) public onlyOperator {
        mintReward();
        uint256 length = _accounts.length;
        require(length == _amounts.length, "Distribution: array length is invalid");
        for (uint256 i = 0; i < length; i++) {
            address account = _accounts[i];
            uint256 amount = _amounts[i];
            require(account != address(0), "Distribution: address is invalid");
            require(amount > 0, "Distribution: amount is invalid");
            PAN.transfer(account, amount);
            emit Distributed(account, amount);
        }
    }

    function setPanPerBlock(uint256 _v) external onlyOwner {
        PANPerBlock = _v;
    }

    function setOperator(address _newOperator) external onlyOwner {
        operator = _newOperator;
    }

    event Distributed(address account, uint256 amount);
    event Claimed(address account, uint256 amount);
}