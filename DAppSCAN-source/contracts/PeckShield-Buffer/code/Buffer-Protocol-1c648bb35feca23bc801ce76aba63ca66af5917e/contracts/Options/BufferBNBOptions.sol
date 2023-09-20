pragma solidity ^0.8.0;

/**
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Buffer
 * Copyright (C) 2020 Buffer Protocol
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

import "../Pool/BufferBNBPool.sol";

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

import "@openzeppelin/contracts/access/Ownable.sol";

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @author Heisenberg
 * @title Buffer BNB Bidirectional (Call and Put) Options
 * @notice Buffer BNB Options Contract
 */
contract BufferBNBOptions is
    IBufferOptions,
    Ownable,
    ERC721,
    ERC721Enumerable,
    ERC721Burnable,
    AccessControl
{
    uint256 public nextTokenId = 0;

    IBufferStakingBNB public settlementFeeRecipient;
    mapping(uint256 => Option) public options;
    uint256 public impliedVolRate;
    uint256 public optionCollateralizationRatio = 100;
    uint256 public settlementFeePercentage = 4;
    uint256 public stakingFeePercentage = 75;
    uint256 public referralRewardPercentage = 50;
    uint256 internal constant PRICE_DECIMALS = 1e8;
    uint256 internal contractCreationTimestamp;
    bool internal migrationProcess = true;
    AggregatorV3Interface public priceProvider;
    BufferBNBPool public pool;

    /**
     * @param pp The address of ChainLink BNB/USD price feed contract
     */
    constructor(
        AggregatorV3Interface pp,
        IBufferStakingBNB staking,
        BufferBNBPool _pool
    ) ERC721("Buffer", "BFR") {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        pool = _pool;
        priceProvider = pp;
        settlementFeeRecipient = staking;
        impliedVolRate = 4500;
        contractCreationTimestamp = block.timestamp;
    }

    /**
     * @notice Used for adjusting the options prices while balancing asset's implied volatility rate
     * @param value New IVRate value
     */
    function setImpliedVolRate(uint256 value) external onlyOwner {
        require(value >= 1000, "ImpliedVolRate limit is too small");
        impliedVolRate = value;
    }

    /**
     * @notice Used for adjusting the settlement fee percentage
     * @param value New Settlement Fee Percentage
     */
    function setSettlementFeePercentage(uint256 value) external onlyOwner {
        require(value < 20, "SettlementFeePercentage is too high");
        settlementFeePercentage = value;
    }

    /**
     * @notice Used for changing settlementFeeRecipient
     * @param recipient New settlementFee recipient address
     */
    function setSettlementFeeRecipient(IBufferStakingBNB recipient)
        external
        onlyOwner
    {
        require(address(recipient) != address(0));
        settlementFeeRecipient = recipient;
    }

    /**
     * @notice Used for adjusting the staking fee percentage
     * @param value New Staking Fee Percentage
     */
    function setStakingFeePercentage(uint256 value) external onlyOwner {
        require(value <= 100, "StakingFeePercentage is too high");
        stakingFeePercentage = value;
    }

    /**
     * @notice Used for adjusting the referral reward percentage
     * @param value New Referral Reward Percentage
     */
    function setReferralRewardPercentage(uint256 value) external onlyOwner {
        require(value <= 100, "ReferralRewardPercentage is too high");
        referralRewardPercentage = value;
    }

    /**
     * @notice Used for changing option collateralization ratio
     * @param value New optionCollateralizationRatio value
     */
    function setOptionCollaterizationRatio(uint256 value) external onlyOwner {
        require(50 <= value && value <= 100, "wrong value");
        optionCollateralizationRatio = value;
    }

        /**
     * @notice Creates a new option
     * @param period Option period in seconds (1 days <= period <= 4 weeks)
     * @param amount Option amount
     * @param strike Strike price of the option
     * @param optionType Call or Put option type
     * @return optionID Created option's ID
     */
     //SWC-107-Reentrancy: L142-L189
    function create(
        uint256 period,
        uint256 amount,
        uint256 strike,
        OptionType optionType,
        address referrer
    ) external payable returns (uint256 optionID) {
        (uint256 totalFee, uint256 settlementFee, uint256 strikeFee, ) = fees(
            period,
            amount,
            strike,
            optionType
        );

        require(
            optionType == OptionType.Call || optionType == OptionType.Put,
            "Wrong option type"
        );
        require(period >= 1 days, "Period is too short");
        require(period <= 90 days, "Period is too long");
        require(amount > strikeFee, "Price difference is too large");
        require(msg.value >= totalFee, "Wrong value");
        if (msg.value > totalFee) {
            payable(msg.sender).transfer(msg.value - totalFee);
        }

        uint256 strikeAmount = amount - strikeFee;
        uint256 lockedAmount = ((strikeAmount * optionCollateralizationRatio) / 100) + strikeFee;

        Option memory option = Option(
            State.Active,
            strike,
            amount,
            lockedAmount,
            totalFee - settlementFee,
            block.timestamp + period,
            optionType
        );

        optionID = createOptionFor(msg.sender);
        options[optionID] = option;

        uint256 stakingAmount = distributeSettlementFee(settlementFee, referrer);

        pool.lock{value: option.premium}(optionID, option.lockedAmount);

        emit Create(optionID, msg.sender, stakingAmount, totalFee);
    }

    /**
     * @notice Check if the sender can exercise an active option
     * @param optionID ID of your option
     */
    function canExercise(uint256 optionID) internal view returns (bool){
        require(_exists(optionID), "ERC721: operator query for nonexistent token");

        address tokenOwner = ERC721.ownerOf(optionID);
        bool isAutoExerciseTrue = autoExerciseStatus[tokenOwner] && msg.sender == owner();

        Option storage option = options[optionID];
        bool isWithinLastHalfHourOfExpiry = block.timestamp > (option.expiration - 30 minutes);
        
        return (tokenOwner == msg.sender) || (isAutoExerciseTrue && isWithinLastHalfHourOfExpiry);
    }

    /**
     * @notice Exercises an active option
     * @param optionID ID of your option
     */
    function exercise(uint256 optionID) external {
        require(
            canExercise(optionID),
            "msg.sender is not eligible to exercise the option"
        );

        Option storage option = options[optionID];

        require(option.expiration >= block.timestamp, "Option has expired");
        require(option.state == State.Active, "Wrong state");

        option.state = State.Exercised;
        uint256 profit = payProfit(optionID);

        // Burn the option
        _burn(optionID);

        emit Exercise(optionID, profit);
    }

    /**
     * @notice Unlocks an array of options
     * @param optionIDs array of options
     */
    function unlockAll(uint256[] calldata optionIDs) external {
        uint256 arrayLength = optionIDs.length;
        for (uint256 i = 0; i < arrayLength; i++) {
            unlock(optionIDs[i]);
        }
    }

    /**
     * @notice Unlock funds locked in the expired options
     * @param optionID ID of the option
     */
    function unlock(uint256 optionID) public {
        Option storage option = options[optionID];
        require(
            option.expiration < block.timestamp,
            "Option has not expired yet"
        );
        require(option.state == State.Active, "Option is not active");
        option.state = State.Expired;
        pool.unlock(optionID);

        // Burn the option
        _burn(optionID);

        emit Expire(optionID, option.premium);
    }

    /**
     * @notice Sends profits in BNB from the BNB pool to an option holder's address
     * @param optionID A specific option contract id
     */
    function payProfit(uint256 optionID) internal returns (uint256 profit) {
        Option memory option = options[optionID];
        (, int256 latestPrice, , , ) = priceProvider.latestRoundData();
        uint256 currentPrice = uint256(latestPrice);
        if (option.optionType == OptionType.Call) {
            require(option.strike <= currentPrice, "Current price is too low");
            profit =
                ((currentPrice - option.strike) * option.amount) /
                currentPrice;
        } else {
            require(option.strike >= currentPrice, "Current price is too high");
            profit =
                ((option.strike - currentPrice) * option.amount) /
                currentPrice;
        }
        // if (profit > option.lockedAmount) profit = option.lockedAmount;
        pool.send(optionID, payable(ownerOf(optionID)), profit);
    }


    function distributeSettlementFee(uint256 settlementFee, address referrer) internal returns (uint256 stakingAmount){
        stakingAmount = ((settlementFee * stakingFeePercentage) / 100);
        
        // Incase the stakingAmount is 0
        if(stakingAmount > 0){
            settlementFeeRecipient.sendProfit{value: stakingAmount}();
        }

        uint256 adminFee = settlementFee - stakingAmount;

        if(adminFee > 0){
            if(referralRewardPercentage > 0 && referrer != owner() && referrer != msg.sender){
                uint256 referralReward = (adminFee * referralRewardPercentage)/100;
                adminFee = adminFee - referralReward;
                payable(referrer).transfer(referralReward);
            }
            payable(owner()).transfer(adminFee);
        }
    }

    /**
     * @notice Used for getting the actual options prices
     * @param period Option period in seconds (1 days <= period <= 4 weeks)
     * @param amount Option amount
     * @param strike Strike price of the option
     * @return total Total price to be paid
     * @return settlementFee Amount to be distributed to the Buffer token holders
     * @return strikeFee Amount that covers the price difference in the ITM options
     * @return periodFee Option period fee amount
     */
    function fees(
        uint256 period,
        uint256 amount,
        uint256 strike,
        OptionType optionType
    )
        public
        view
        returns (
            uint256 total,
            uint256 settlementFee,
            uint256 strikeFee,
            uint256 periodFee
        )
    {
        (, int256 latestPrice, , , ) = priceProvider.latestRoundData();
        uint256 currentPrice = uint256(latestPrice);
        settlementFee = getSettlementFee(amount);
        periodFee = getPeriodFee(
            amount,
            period,
            strike,
            currentPrice,
            optionType
        );
        strikeFee = getStrikeFee(amount, strike, currentPrice, optionType);
        total = periodFee + strikeFee + settlementFee;
    }


    /**
     * @notice Calculates periodFee
     * @param amount Option amount
     * @param period Option period in seconds (1 days <= period <= 4 weeks)
     * @param strike Strike price of the option
     * @param currentPrice Current price of BNB
     * @return fee Period fee amount
     *
     * amount < 1e30        |
     * impliedVolRate < 1e10| => amount * impliedVolRate * strike < 1e60 < 2^uint256
     * strike < 1e20 ($1T)  |
     *
     * in case amount * impliedVolRate * strike >= 2^256
     * transaction will be reverted by the SafeMath
     */
    function getPeriodFee(
        uint256 amount,
        uint256 period,
        uint256 strike,
        uint256 currentPrice,
        OptionType optionType
    ) internal view returns (uint256 fee) {
        if (optionType == OptionType.Put)
            return
                (amount * sqrt(period) * impliedVolRate * strike) /
                (currentPrice * PRICE_DECIMALS);
        else
            return
                (amount * sqrt(period) * impliedVolRate * currentPrice) /
                (strike * PRICE_DECIMALS);
    }

    /**
     * @notice Calculates strikeFee
     * @param amount Option amount
     * @param strike Strike price of the option
     * @param currentPrice Current price of BNB
     * @return fee Strike fee amount
     */
    function getStrikeFee(
        uint256 amount,
        uint256 strike,
        uint256 currentPrice,
        OptionType optionType
    ) internal pure returns (uint256 fee) {
        if (strike > currentPrice && optionType == OptionType.Put)
            return ((strike - currentPrice) * amount) / currentPrice;
        if (strike < currentPrice && optionType == OptionType.Call)
            return ((currentPrice - strike) * amount) / currentPrice;
        return 0;
    }

    /**
     * @notice Calculates settlementFee
     * @param amount Option amount
     * @return fee Settlement fee amount
     */
    function getSettlementFee(uint256 amount)
        internal
        view
        returns (uint256 fee)
    {
        return (amount * settlementFeePercentage) / 100;
    }

    /**
     * @dev See EIP-165: ERC-165 Standard Interface Detection
     * https://eips.ethereum.org/EIPS/eip-165
     **/
    function createOptionFor(address holder) internal returns (uint256 id) {
        id = nextTokenId++;
        _safeMint(holder, id);
    }

    /**
     * @dev Template code provided by OpenZepplin Code Wizard
     */
    function _baseURI() internal pure override returns (string memory) {
        return "https://buffer.finance";
    }

    // The following functions are overrides required by Solidity.

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override(ERC721, ERC721Enumerable) {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    /**
     * @return result Square root of the number
     */
    function sqrt(uint256 x) internal pure returns (uint256 result) {
        result = x;
        uint256 k = (x / 2) + 1;
        while (k < result) (result, k) = (k, ((x / k) + k) / 2);
    }

    /**
     * Exercise Approval
     */

    // Mapping from owner to exerciser approvals
    mapping(address => bool) public autoExerciseStatus;

    event AutoExerciseStatusChange(address indexed account, bool status);

    function setAutoExerciseStatus(bool status) public {
        autoExerciseStatus[msg.sender] = status;
        emit AutoExerciseStatusChange(msg.sender, status);
    }

}