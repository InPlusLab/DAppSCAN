// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

interface IERC20 {
    // ERC20 Optional Views
    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function decimals() external view returns (uint8);

    // Views
    function totalSupply() external view returns (uint256);

    function balanceOf(address owner) external view returns (uint256);

    function allowance(address owner, address spender)
        external
        view
        returns (uint256);

    // Mutative functions
    function transfer(address to, uint256 value) external returns (bool);

    function approve(address spender, uint256 value) external returns (bool);

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external returns (bool);

    // Events
    event Transfer(address indexed from, address indexed to, uint256 value);

    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
}

contract Lockup {
    address payable foilWallet;
    mapping(address => mapping(uint256 => uint256)) public deposits;

    // USDT instance
    IERC20 public usdt;

    //event
    event Deposit(address userAddress, uint256 indexed side, uint256 amount);
    event Withdraw(uint256 amountAfterPercent);
//SWC-135-Code With No Effects: L55
    constructor(address payable _foilWallet, address _usdt) {
        require(_foilWallet != address(0), "The wallet address can not zero.");
        require(_usdt != address(0), "The USDT address can not zero.");
        foilWallet = _foilWallet;
        usdt = IERC20(_usdt);
    }

    function deposit(uint256 amount, uint256 side)
        external
        payable
        returns (bool)
    {
        require(msg.value == amount);
        deposits[msg.sender][side] = deposits[msg.sender][side] + amount;

        emit Deposit(msg.sender, side, amount);

        return true;
    }

    receive() external payable {}

    function getBalance() public view returns (uint256) {
        return address(this).balance;
    }

    function withdraw(uint256 percentage, uint256 side) external {
        uint256 amount = deposits[msg.sender][side];
        require(amount > 0, "Can not withdraw");
        deposits[msg.sender][side] = deposits[msg.sender][side] - (amount * percentage);
        uint256 amountAfterPercent = (amount * percentage) / 1e4;

        if (side == 1) {
            require(
                usdt.transfer(foilWallet, amountAfterPercent),
                "Insufficient!"
            );
        } else {
            foilWallet.transfer(amountAfterPercent);
        }

        emit Withdraw(amountAfterPercent);
    }
}
