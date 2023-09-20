// SPDX-License-Identifier: Unlicensed
// SWC-102-Outdated Compiler Version: L3
pragma solidity 0.8.11;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";


contract TravelCare is
    Ownable,
    ERC20
{
    uint256 public immutable CAP;

    address public marketingWallet;
    uint256 public marketingFee;
    uint256 public burningFee;
    uint256 public maxTxAmount;

    mapping(address => bool) public isExcludedFromFee;

    enum RewardType {
        None,
        Pink_Flamingo,
        Indigo_Bunting,
        Purple_Martin,
        Golden_Eagle,
        Arctic_Tern
    }

    struct RewardTypeInfo {
        uint256 minDuration;
        uint256 minBalance;
    }

    mapping(RewardType => RewardTypeInfo) public categories;

    mapping(address => mapping(RewardType => uint256)) public userToRewardTypeTimestamp;

    constructor(
        address _marketingWallet,
        uint256 _marketingFee,
        uint256 _burningFee,
        uint256 _maxTxAmount
    ) ERC20("TravelCare", "TRAVEL") {
        marketingWallet = _marketingWallet;
        marketingFee = _marketingFee;
        burningFee = _burningFee;
        maxTxAmount = _maxTxAmount;

        isExcludedFromFee[address(this)] = true;
        isExcludedFromFee[msg.sender] = true;

        CAP = 210_000_000 * (10 ** decimals());

        categories[RewardType.Pink_Flamingo] =
            RewardTypeInfo(0, 1000 * (10 ** decimals()));

        categories[RewardType.Indigo_Bunting] =
            RewardTypeInfo(30 days, 11_000 * (10 ** decimals()));

        categories[RewardType.Purple_Martin] =
            RewardTypeInfo(60 days, 63_000 * (10 ** decimals()));

        categories[RewardType.Golden_Eagle] =
            RewardTypeInfo(120 days, 210_000 * (10 ** decimals()));

        categories[RewardType.Arctic_Tern] =
            RewardTypeInfo(180 days, 840_000 * (10 ** decimals()));

        _mint(
            msg.sender,
            CAP
        );
    }

    function getUserRewardStatus(address account)
        public
        view
        returns (RewardType)
    {
        mapping(RewardType => uint256) storage userRewardsToTimestamp = userToRewardTypeTimestamp[account];

        if (
            userRewardsToTimestamp[RewardType.Arctic_Tern] != 0 &&
            (
                block.timestamp - userRewardsToTimestamp[RewardType.Arctic_Tern]
                >= categories[RewardType.Arctic_Tern].minDuration
            )
        )
            return RewardType.Arctic_Tern;

        if (
            userRewardsToTimestamp[RewardType.Golden_Eagle] != 0 &&
            (
                block.timestamp - userRewardsToTimestamp[RewardType.Golden_Eagle]
                >= categories[RewardType.Golden_Eagle].minDuration
            )
        )
            return RewardType.Golden_Eagle;

        if (
            userRewardsToTimestamp[RewardType.Purple_Martin] != 0 &&
            (
                block.timestamp - userRewardsToTimestamp[RewardType.Purple_Martin]
                >= categories[RewardType.Purple_Martin].minDuration
            )
        )
            return RewardType.Purple_Martin;

        if (
            userRewardsToTimestamp[RewardType.Indigo_Bunting] != 0 &&
            (
                block.timestamp - userRewardsToTimestamp[RewardType.Indigo_Bunting]
                >= categories[RewardType.Indigo_Bunting].minDuration
            )
        )
            return RewardType.Indigo_Bunting;

        if (
            userRewardsToTimestamp[RewardType.Pink_Flamingo] != 0 &&
            (
                block.timestamp - userRewardsToTimestamp[RewardType.Pink_Flamingo]
                >= categories[RewardType.Pink_Flamingo].minDuration
            )
        )
            return RewardType.Pink_Flamingo;

        return RewardType.None;
    }

    receive() external payable {}

    function changeRewardRequirements(
        RewardType _rewardType,
        uint256 _newAmount,
        uint256 _newDuration
    ) external onlyOwner {
        require(
            uint8(_rewardType) > uint8(RewardType.None),
            "TravelCare::changeRewardRequirements: invalid reward type"
        );

        categories[_rewardType] = RewardTypeInfo(_newDuration, _newAmount);
    }

    function mint(address _to, uint256 _amount)
        external
        onlyOwner
    {
        require(
           totalSupply() + _amount <= CAP,
            "TravelCare::mint: minting exceeds CAP"
        );

        _mint(
            _to,
            _amount
        );
    }

    function burn(uint256 _amount) external {
        _burn(_msgSender(), _amount);
    }

    function burnFrom(address _from, uint256 _amount) external {
        uint256 currentAllowance = allowance(_from, _msgSender());
        _approve(
            _from,
            _msgSender(),
            currentAllowance - _amount
        );
        _burn(_from, _amount);
    }

    function excludeFromFee(address _account, bool exclude)
        external
        onlyOwner
    {
        isExcludedFromFee[_account] = exclude;
    }

    function setMarketingFee(uint256 _marketingFee)
        external
        onlyOwner
    {
        marketingFee = _marketingFee;
    }

    function setBurningFee(uint256 _burningFee)
        external
        onlyOwner
    {
        burningFee = _burningFee;
    }

    function setMaxTxAmount(uint256 _maxTxAmount)
        external
        onlyOwner
    {
        maxTxAmount = _maxTxAmount;
    }

    function withdrawBNB(uint256 _amount)
        external
        onlyOwner
    {
        payable(msg.sender).transfer(_amount);
    }

    function withdrawToken(address _token, uint256 _amount)
        external
        onlyOwner
    {
        IERC20(_token).transfer(msg.sender, _amount);
    }

    function setMarketingWallet(address _marketingWallet)
        external
        onlyOwner
    {
        marketingWallet = _marketingWallet;
    }

    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal override {
        require(
            sender != address(0),
            "ERC20::_transfer: transfer from the zero address"
        );

        require(
            recipient != address(0),
            "ERC20::_transfer: transfer to the zero address"
        );

        address _owner = owner();
        if (sender != _owner && recipient != _owner)
            require(
                amount <= maxTxAmount,
                "ERC20::_transfer: amount exceeds maxTxAmount"
            );

        bool takeFee = !isExcludedFromFee[sender] && !isExcludedFromFee[recipient];
        if (takeFee) {
            (
                uint256 burnFeeCollected,
                uint256 marketingFeeCollected
            ) = processFee(sender, amount);

            amount = amount
                - burnFeeCollected
                - marketingFeeCollected;
        }

        ERC20._transfer(
            sender,
            recipient,
            amount
        );
    }

    function processFee(address _account, uint256 _tokenAmount)
        private
        returns(
            uint256 burnFeeCollected,
            uint256 marketingFeeCollected
        )
    {
        burnFeeCollected = _tokenAmount * burningFee / 100;
        marketingFeeCollected = _tokenAmount * marketingFee / 100;

        _balances[_account] = _balances[_account]
            - burnFeeCollected
            - marketingFeeCollected;

        _totalSupply = _totalSupply - burnFeeCollected;
        _balances[marketingWallet] = _balances[marketingWallet] + marketingFeeCollected;

        return (
            burnFeeCollected,
            marketingFeeCollected
        );
    }

    function addEligibleRewards(address account) private {
        mapping(RewardType => uint256) storage userRewardsToTimestamp = userToRewardTypeTimestamp[account];
        uint256 balance = balanceOf(account);

        if (
            userRewardsToTimestamp[RewardType.Pink_Flamingo] == 0 &&
            balance >= categories[RewardType.Pink_Flamingo].minBalance
        )
            userRewardsToTimestamp[RewardType.Pink_Flamingo] = block.timestamp;

        if (
            userRewardsToTimestamp[RewardType.Indigo_Bunting] == 0 &&
            balance >= categories[RewardType.Indigo_Bunting].minBalance
        )
            userRewardsToTimestamp[RewardType.Indigo_Bunting] = block.timestamp;

        if (
            userRewardsToTimestamp[RewardType.Purple_Martin] == 0 &&
            balance >= categories[RewardType.Purple_Martin].minBalance
        )
            userRewardsToTimestamp[RewardType.Purple_Martin] = block.timestamp;

        if (
            userRewardsToTimestamp[RewardType.Golden_Eagle] == 0 &&
            balance >= categories[RewardType.Golden_Eagle].minBalance
        )
            userRewardsToTimestamp[RewardType.Golden_Eagle] = block.timestamp;

        if (
            userRewardsToTimestamp[RewardType.Arctic_Tern] == 0 &&
            balance >= categories[RewardType.Arctic_Tern].minBalance
        )
            userRewardsToTimestamp[RewardType.Arctic_Tern] = block.timestamp;
    }

    function removeOutstandingRewards(address account) private {
        mapping(RewardType => uint256) storage userRewardsToTimestamp = userToRewardTypeTimestamp[account];
        uint256 balance = balanceOf(account);

        if (
            userRewardsToTimestamp[RewardType.Pink_Flamingo] != 0 &&
            balance < categories[RewardType.Pink_Flamingo].minBalance
        )
            userRewardsToTimestamp[RewardType.Pink_Flamingo] = 0;

        if (
            userRewardsToTimestamp[RewardType.Indigo_Bunting] != 0 &&
            balance < categories[RewardType.Indigo_Bunting].minBalance
        )
            userRewardsToTimestamp[RewardType.Indigo_Bunting] = 0;

        if (
            userRewardsToTimestamp[RewardType.Purple_Martin] != 0 &&
            balance < categories[RewardType.Purple_Martin].minBalance
        )
            userRewardsToTimestamp[RewardType.Purple_Martin] = 0;

        if (
            userRewardsToTimestamp[RewardType.Golden_Eagle] != 0 &&
            balance < categories[RewardType.Golden_Eagle].minBalance
        )
            userRewardsToTimestamp[RewardType.Golden_Eagle] = 0;

        if (
            userRewardsToTimestamp[RewardType.Arctic_Tern] != 0 &&
            balance < categories[RewardType.Arctic_Tern].minBalance
        )
            userRewardsToTimestamp[RewardType.Arctic_Tern] = 0;
    }

    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        super._afterTokenTransfer(
            from,
            to,
            amount
        );

        if (from != address(0))
            removeOutstandingRewards(from);

        if (to != address(0))
            addEligibleRewards(to);
    }
}
