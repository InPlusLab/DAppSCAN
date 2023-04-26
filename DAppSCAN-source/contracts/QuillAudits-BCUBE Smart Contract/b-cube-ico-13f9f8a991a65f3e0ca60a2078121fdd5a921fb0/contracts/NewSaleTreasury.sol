// SPDX-License-Identifier: Unlicense
pragma solidity 0.5.17;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./B3NewSale.sol";

/**
 * @title BCUBE Treasury for Public Sale
 * @notice Contract in which 15m BCUBE will be transfered after public sale,
 * and distributed to stakeholders to whomever applicable
 **/

contract NewSaleTreasury is B3NewSale {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    modifier onlyAfterListing() {
        require(now >= listingTime, "Only callable after listing");
        _;
    }

    /// @notice timestamp at which BCUBE will be listed on CEXes/DEXes
    uint256 public listingTime;

    IERC20 public token;

    event LogListingTimeChange(uint256 prevListingTime, uint256 newListingTime);
    event LogPublicSaleShareWithdrawn(
        address indexed participant,
        uint256 bcubeAmountWithdrawn
    );

    constructor(
        address payable _wallet,
        address _admin,
        IERC20 _token,
        uint256 _openingTime,
        uint256 _closingTime,
        address _chainlinkETHPriceFeed,
        address _chainlinkUSDTPriceFeed,
        address _usdtContract,
        uint256 _listingTime
    )
        public
        B3NewSale(
            _openingTime,
            _closingTime,
            _chainlinkETHPriceFeed,
            _chainlinkUSDTPriceFeed,
            _usdtContract,
            _wallet
        )
    {
        setAdmin(_admin);
        token = _token;
        listingTime = _listingTime;
    }

    /// @dev WhitelistAdmin is the deployer
    /// @dev allows deployer to change listingTime, before current listingTime
    function setListingTime(uint256 _startTime) external onlyWhitelistAdmin {
        require(now < listingTime, "listingTime unchangable after listing");
        uint256 prevListingTime = listingTime;
        listingTime = _startTime;
        emit LogListingTimeChange(prevListingTime, listingTime);
    }

    function calcAllowance(address _who, uint256 _when)
        public
        view
        returns (uint256)
    {
        uint256 allowance;
        uint256 allocatedBCUBEs =
            bcubeAllocationRegistry[_who].allocatedBCUBE.div(12);
        if (_when >= listingTime + 11 weeks) {
            // 100% of allocated tokens
            allowance = bcubeAllocationRegistry[_who].allocatedBCUBE;
        } else if (_when >= listingTime + 10 weeks) {
            // 11 * 8.33% of allocated tokens
            allowance = allocatedBCUBEs.mul(11);
        } else if (_when >= listingTime + 9 weeks) {
            // 10 * 8.33% allocated tokens
            allowance = allocatedBCUBEs.mul(10);
        } else if (_when >= listingTime + 8 weeks) {
            // 9 * 8.33% allocated tokens
            allowance = allocatedBCUBEs.mul(9);
        } else if (_when >= listingTime + 7 weeks) {
            // 8 * 8.33% allocated tokens
            allowance = allocatedBCUBEs.mul(8);
        } else if (_when >= listingTime + 6 weeks) {
            // 7 * 8.33% allocated tokens
            allowance = allocatedBCUBEs.mul(7);
        } else if (_when >= listingTime + 5 weeks) {
            // 6 * 8.33% allocated tokens
            allowance = allocatedBCUBEs.mul(6);
        } else if (_when >= listingTime + 4 weeks) {
            // 5 * 8.33% allocated tokens
            allowance = allocatedBCUBEs.mul(5);
        } else if (_when >= listingTime + 3 weeks) {
            // 4 * 8.33% allocated tokens
            allowance = allocatedBCUBEs.mul(4);
        } else if (_when >= listingTime + 2 weeks) {
            // 3 * 8.33% allocated tokens
            allowance = allocatedBCUBEs.mul(3);
        } else if (_when >= listingTime + 1 weeks) {
            // 2 * 8.33% allocated tokens
            allowance = allocatedBCUBEs.mul(2);
        } else if (_when >= listingTime) {
            // 8.33% allocated tokens
            allowance = allocatedBCUBEs;
        }
        return allowance;
    }

    /// @dev allows public sale participants to withdraw their allocated share of
    function shareWithdraw(uint256 bcubeAmount)
        external
        onlyAfterListing
        nonReentrant
    {
        require(
            bcubeAllocationRegistry[_msgSender()].allocatedBCUBE > 0,
            "!saleParticipant || 0 BCUBE allocated"
        );

        uint256 allowance = calcAllowance(_msgSender(), now);
        if (allowance != bcubeAllocationRegistry[_msgSender()].currentAllowance)
            bcubeAllocationRegistry[_msgSender()].currentAllowance = allowance;

        uint256 finalWithdrawn =
            bcubeAllocationRegistry[_msgSender()].shareWithdrawn.add(
                bcubeAmount
            );
        require(
            finalWithdrawn <=
                bcubeAllocationRegistry[_msgSender()].currentAllowance,
            "Insufficient allowance"
        );
        bcubeAllocationRegistry[_msgSender()].shareWithdrawn = finalWithdrawn;
        token.safeTransfer(_msgSender(), bcubeAmount);
        emit LogPublicSaleShareWithdrawn(_msgSender(), bcubeAmount);
    }
}
