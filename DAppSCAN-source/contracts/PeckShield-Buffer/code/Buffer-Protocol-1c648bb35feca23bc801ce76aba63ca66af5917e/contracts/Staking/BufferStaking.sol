// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "../Interfaces/Interfaces.sol";

/**
 * @author Heisenberg
 * @title Buffer BNB Staking Pool
 * @notice Parent class for the Staking Pools
 */
abstract contract BufferStaking is ERC20, IBufferStaking {
    IERC20 public immutable BUFFER;
    uint256 public constant ACCURACY = 1e30;
    address payable public immutable FALLBACK_RECIPIENT;

    /**
     * @dev Returns the Max Supply of the token.
     */
    function maxSupply() public view virtual returns (uint256) {
        return 1e5;
    }

    /**
     * @dev Returns the Max Supply of the token.
     */
    function lotPrice() public view virtual returns (uint256) {
        return 1000e18;
    }

    uint256 public totalProfit = 0;
    mapping(address => uint256) internal lastProfit;
    mapping(address => uint256) internal savedProfit;

    uint256 public lockupPeriod = 1 days;
    mapping(address => uint256) public lastBoughtTimestamp;
    mapping(address => bool) public _revertTransfersInLockUpPeriod;

    constructor(
        ERC20 _token,
        string memory name,
        string memory short
    ) ERC20(name, short) {
        BUFFER = _token;
        FALLBACK_RECIPIENT = payable(msg.sender);
    }

    function claimProfit() external override returns (uint256 profit) {
        profit = saveProfit(msg.sender);
        require(profit > 0, "Zero profit");
        savedProfit[msg.sender] = 0;
        _transferProfit(profit);
        emit Claim(msg.sender, profit);
    }

    function buy(uint256 amountOfTokens) external override {
        lastBoughtTimestamp[msg.sender] = block.timestamp;
        require(amountOfTokens > 0, "Amount is zero");
        require(totalSupply() + amountOfTokens <= maxSupply());
        _mint(msg.sender, amountOfTokens);
        BUFFER.transferFrom(msg.sender, address(this), amountOfTokens * lotPrice());
    }

    function sell(uint256 amountOfTokens) external override lockupFree {
        _burn(msg.sender, amountOfTokens);
        BUFFER.transfer(msg.sender, amountOfTokens * lotPrice());
    }

    /**
     * @notice Used for ...
     */
    function revertTransfersInLockUpPeriod(bool value) external {
        _revertTransfersInLockUpPeriod[msg.sender] = value;
    }

    function profitOf(address account)
        external
        view
        override
        returns (uint256)
    {
        return savedProfit[account] + getUnsaved(account);
    }

    function getUnsaved(address account)
        internal
        view
        returns (uint256 profit)
    {
        return
            ((totalProfit - lastProfit[account]) * balanceOf(account)) /
            ACCURACY;
    }

    function saveProfit(address account) internal returns (uint256 profit) {
        uint256 unsaved = getUnsaved(account);
        lastProfit[account] = totalProfit;
        profit = savedProfit[account] + unsaved;
        savedProfit[account] = profit;
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256
    ) internal override {
        if (from != address(0)) saveProfit(from);
        if (to != address(0)) saveProfit(to);
        if (
            lastBoughtTimestamp[from] + lockupPeriod > block.timestamp &&
            lastBoughtTimestamp[from] > lastBoughtTimestamp[to]
        ) {
            require(
                !_revertTransfersInLockUpPeriod[to],
                "the recipient does not accept blocked funds"
            );
            lastBoughtTimestamp[to] = lastBoughtTimestamp[from];
        }
    }

    function _transferProfit(uint256 amount) internal virtual;

    modifier lockupFree() {
        require(
            lastBoughtTimestamp[msg.sender] + lockupPeriod <= block.timestamp,
            "Action suspended due to lockup"
        );
        _;
    }
}
