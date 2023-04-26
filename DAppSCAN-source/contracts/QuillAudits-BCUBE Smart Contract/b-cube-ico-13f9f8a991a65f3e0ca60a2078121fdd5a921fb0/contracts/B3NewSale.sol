pragma solidity 0.5.17;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/drafts/SignedSafeMath.sol";
import "@openzeppelin/contracts/utils/SafeCast.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/access/roles/WhitelistedRole.sol";
import "@openzeppelin/contracts/lifecycle/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@chainlink/contracts/src/v0.5/interfaces/AggregatorV3Interface.sol";

contract B3NewSale is WhitelistedRole, ReentrancyGuard {
    using SafeMath for uint256;
    using SignedSafeMath for int256;
    using SafeCast for uint256;
    using SafeERC20 for IERC20;

    mapping(address => UserInfo) public bcubeAllocationRegistry;

    /// @dev variables whose instance fetch prices of USDT, ETH from Chainlink oracles
    AggregatorV3Interface internal priceFeedETH;
    AggregatorV3Interface internal priceFeedUSDT;

    IERC20 public usdt;

    uint256 public openingTime;
    uint256 public closingTime;

    uint256 public constant HARD_CAP = 900_000e18; // 1 Million
    uint256 public constant BCUBE_PRICE_PER_USDT = 16666666666; // 0.6 USDT
    // Maxium Contribution Per Wallet, e8 since USDT has 8 decimals
    uint256 public constant MAXIMUM_CONTRIBUTION_PER_WALLET = 1_000_0e8;

    // 1 dollar = 100,000,000 dollar units
    // Minimum contribution in Dollar Units
    uint256 public minContributionDollarUnits = 500e8; // $500
    // Maxium contribution in Dollar Units
    uint256 public maxContributionDollarUnits = 2500e8; // $2.5k

    uint256 public netSoldBcube;

    // Address where funds are collected
    address payable private wallet;

    /// @dev allowance is # of BCUBE each participant can withdraw from treasury.
    /// @param currentAllowance this allowance is in 4 stages tracked by currentAllowance
    /// @param shareWithdrawn tracks the amount of BCUBE already withdrawn from treasury
    /// @param dollarUnitsPayed 1 dollar = 100,000,000 dollar units.
    /// This tracks dollar units payed by user to this contract
    struct UserInfo {
        uint256 dollarUnitsPayed;
        uint256 allocatedBCUBE;
        uint256 currentAllowance;
        uint256 shareWithdrawn;
    }

    modifier onlyWhitelisted() {
        require(
            isWhitelisted(_msgSender()),
            "B3NewSale: caller does not have the Whitelisted role"
        );
        _;
    }

    modifier onlyWhileOpen {
        require(isOpen(), "B3NewSale: not open");
        _;
    }

    /// @dev ensuring BCUBE allocations in public sale don't exceed 1 Million
    modifier tokensRemaining() {
        require(netSoldBcube <= HARD_CAP, "B3NewSale: All tokens sold");
        _;
    }

    event LogEtherReceived(address indexed sender, uint256 value);
    event LogBcubeBuyUsingEth(
        address indexed buyer,
        uint256 incomingWei,
        uint256 allocation
    );
    event LogBcubeBuyUsingUsdt(
        address indexed buyer,
        uint256 incomingUsdtUnits,
        uint256 allocation
    );
    event LogETHPriceFeedChange(address indexed newChainlinkETHPriceFeed);
    event LogUSDTPriceFeedChange(address indexed newChainlinkUSDTPriceFeed);
    event LogUSDTInstanceChange(address indexed newUsdtContract);
    event LogPublicSaleTimeExtension(
        uint256 previousClosingTime,
        uint256 newClosingTime
    );
    event LogLimitChanged(uint256 _newMin, uint256 _newMax);

    /**
     * @param _openingTime public sale starting time
     * @param _closingTime public sale closing time
     * @param _chainlinkETHPriceFeed address of the ETH price feed
     * @param _chainlinkUSDTPriceFeed address of the USDT price feed
     * @param _usdtContract address of the USDT ERC20 contract
     * @param _wallet team wallet: where ETH end USDT will be transferred
     */
    constructor(
        uint256 _openingTime,
        uint256 _closingTime,
        address _chainlinkETHPriceFeed,
        address _chainlinkUSDTPriceFeed,
        address _usdtContract,
        address payable _wallet
    ) public WhitelistedRole() {
        openingTime = _openingTime;
        closingTime = _closingTime;
        priceFeedETH = AggregatorV3Interface(_chainlinkETHPriceFeed);
        priceFeedUSDT = AggregatorV3Interface(_chainlinkUSDTPriceFeed);
        usdt = IERC20(_usdtContract);
        wallet = _wallet;
    }

    /**
     * @dev To set admin
     * Requirements
     * - Can only be invoked by white listed admins
     */
    function setAdmin(address _admin) public onlyWhitelistAdmin {
        // Add new admin for whitelisting, and remove msgSender as admin
        addWhitelistAdmin(_admin);
        renounceWhitelistAdmin();
    }

    /**
     * @dev To update $ Contribution limits
     * Requirements
     * - Can only be invoked by white listed admins
     */
    function setContributionsLimits(uint256 _min, uint256 _max)
        public
        onlyWhitelistAdmin
    {
        minContributionDollarUnits = _min;
        maxContributionDollarUnits = _max;
        emit LogLimitChanged(_min, _max);
    }

    /**
     * @dev The fallback function is executed on a call to the contract if
     * none of the other functions match the given function signature.
     */
    function() external payable {
        emit LogEtherReceived(_msgSender(), msg.value);
    }

    /**
     * @dev Checks and returns if sale is open or not
     */
    function isOpen() public view returns (bool) {
        // solhint-disable-next-line not-rely-on-time
        return block.timestamp >= openingTime && block.timestamp <= closingTime;
    }

    /**
     * @dev Returns the HARD_CAP value
     */
    function hardcap() public view returns (uint256) {
        return HARD_CAP;
    }

    /**
     * @dev allowing resetting ETH priceFeed instance, in case current Chainlink contracts upgrade
     */
    function setETHPriceFeed(address _newChainlinkETHPriceFeed)
        external
        onlyWhitelistAdmin
    {
        priceFeedETH = AggregatorV3Interface(_newChainlinkETHPriceFeed);
        emit LogETHPriceFeedChange(_newChainlinkETHPriceFeed);
    }

    /**
     * @dev allowing resetting USDT priceFeed instance, in case current Chainlink contracts upgrade
     */
    function setUSDTPriceFeed(address _newChainlinkUSDTPriceFeed)
        external
        onlyWhitelistAdmin
    {
        priceFeedUSDT = AggregatorV3Interface(_newChainlinkUSDTPriceFeed);
        emit LogUSDTPriceFeedChange(_newChainlinkUSDTPriceFeed);
    }

    /**
     * @dev allowing resetting USDT instance, in case current contract upgrades
     */
    function setUSDTInstance(address _newUsdtContract)
        external
        onlyWhitelistAdmin
    {
        usdt = IERC20(_newUsdtContract);
        emit LogUSDTInstanceChange(_newUsdtContract);
    }

    /**
     * @dev To extend the current closing time of public sale
     */
    function extendClosingTime(uint256 _newClosingTime)
        external
        onlyWhitelistAdmin
    {
        emit LogPublicSaleTimeExtension(closingTime, _newClosingTime);
        closingTime = _newClosingTime;
    }

    /**
     * @dev allowing users to allocate BCUBEs for themselves using ETH
     * It fetches current price of ETH, multiples that by incoming ETH to calc total incoming dollar units, then
     * allocates appropriate amount of BCUBE to user based on current rate, stage
     * Requirements:
     * - only KYC/AML whitelisted users can call this, while the sale is open and allocation hard cap is not reached
     * - can be called only when sale is open
     * - will only succeed if tokens are remaining
     */
    function buyBcubeUsingETH()
        external
        payable
        onlyWhitelisted
        onlyWhileOpen
        tokensRemaining
        nonReentrant
    {
        uint256 allocation;
        uint256 ethPrice = uint256(fetchETHPrice());
        uint256 dollarUnits = ethPrice.mul(msg.value).div(1e18);
        allocation = executeAllocation(dollarUnits);
        wallet.transfer(msg.value);
        emit LogBcubeBuyUsingEth(_msgSender(), msg.value, allocation);
    }

    /**
     * @dev Allows users to allocate BCUBEs for themselves using USDT
     */
    function buyBcubeUsingUSDT(uint256 incomingUsdt)
        external
        onlyWhitelisted
        onlyWhileOpen
        tokensRemaining
        nonReentrant
    {
        uint256 allocation;
        uint256 usdtPrice = uint256(fetchUSDTPrice());
        uint256 dollarUnits = usdtPrice.mul(incomingUsdt).div(1e6);
        allocation = executeAllocation(dollarUnits);
        usdt.safeTransferFrom(_msgSender(), wallet, incomingUsdt);
        emit LogBcubeBuyUsingUsdt(_msgSender(), incomingUsdt, allocation);
    }

    /**
     * @dev Returns the BCUBE that will be allocated to the caller
     *
     * Requirements:
     * - dollarUnits >= $500 && dollarUnits <= $2500
     * - totalContribution <= $10000 Per Wallet
     * - netSoldBcube <= HARD_CAP
     */
    function executeAllocation(uint256 dollarUnits) private returns (uint256) {
        uint256 bcubeAllocatedToUser;
        require(
            dollarUnits >= minContributionDollarUnits,
            "B3NewSale: Min contrbn $500 not reached."
        );
        require(
            dollarUnits <= maxContributionDollarUnits,
            "B3NewSale: Exceeds max contrbn $2500 limit"
        );
        uint256 totalContribution =
            bcubeAllocationRegistry[_msgSender()].dollarUnitsPayed.add(
                dollarUnits
            );
        require(
            totalContribution <= MAXIMUM_CONTRIBUTION_PER_WALLET,
            "B3NewSale: Exceeds total max contribn $10000"
        );
        bcubeAllocatedToUser = BCUBE_PRICE_PER_USDT.mul(dollarUnits);
        netSoldBcube = netSoldBcube.add(bcubeAllocatedToUser);
        require(netSoldBcube <= HARD_CAP, "B3NewSale: Exceeds hard cap");
        // Updates dollarUnitsPayed in storage
        bcubeAllocationRegistry[_msgSender()]
            .dollarUnitsPayed = totalContribution;
        // Updates allocatedBCUBE in storage
        bcubeAllocationRegistry[_msgSender()]
            .allocatedBCUBE = bcubeAllocationRegistry[_msgSender()]
            .allocatedBCUBE
            .add(bcubeAllocatedToUser);
        return bcubeAllocatedToUser;
    }

    /**
     * @dev Fetches ETH price from chainlink oracle
     */
    function fetchETHPrice() public view returns (uint256) {
        (, int256 price, , , ) = priceFeedETH.latestRoundData();
        return toUint256(price);
    }

    /**
     * @dev Fetches USDT price from chainlink oracle
     */
    function fetchUSDTPrice() public view returns (uint256) {
        (, int256 price, , , ) = priceFeedUSDT.latestRoundData();
        uint256 ethUSD = fetchETHPrice();
        return toUint256(price).mul(ethUSD).div(1e18);
    }

    /**
     * @dev Casts int256 to uint256
     */
    function toUint256(int256 value) internal pure returns (uint256) {
        require(value >= 0, "SafeCast: value must be positive");
        return uint256(value);
    }
}
