// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import '../Arth/IARTH.sol';
import '../ARTHX/IARTHX.sol';
import '../ERC20/IERC20.sol';
import '../utils/math/SafeMath.sol';
import '../Arth/Pools/IARTHPool.sol';
import '../ERC20/Variants/Comp.sol';
import './compound/IcUSDC_Partial.sol';
import './yearn/IyUSDC_V2_Partial.sol';
import './aave/IAAVE_aUSDC_Partial.sol';
import '../Oracle/UniswapPairOracle.sol';
import '../access/AccessControl.sol';
import './aave/IAAVELendingPool_Partial.sol';
import './compound/ICompComptrollerPartial.sol';
import '../Arth/IARTHController.sol';

/**
 *  Original code written by:
 *  - Travis Moore, Jason Huan, Same Kazemian, Sam Sun.
 *  Code modified by:
 *  - Steven Enamakel, Yash Agrawal & Sagar Behara.
 *  Lower APY: yearn, AAVE, Compound
 *  Higher APY: KeeperDAO, BZX, Harvest
 */
contract ArthPoolInvestorForV2 is AccessControl {
    using SafeMath for uint256;

    /* ========== STATE VARIABLES ========== */

    IERC20 private collateralToken;
    IARTHX private ARTHX;
    IARTH private ARTH;
    IARTHPool private pool;
    IARTHController private controller;

    // Pools and vaults
    IyUSDC_V2_Partial private yUSDC_V2 =
        IyUSDC_V2_Partial(0x5f18C75AbDAe578b483E5F43f12a39cF75b973a9);
    IAAVELendingPool_Partial private aaveUSDC_Pool =
        IAAVELendingPool_Partial(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);
    IAAVE_aUSDC_Partial private aaveUSDC_Token =
        IAAVE_aUSDC_Partial(0xBcca60bB61934080951369a648Fb03DF4F96263C);
    IcUSDC_Partial private cUSDC =
        IcUSDC_Partial(0x39AA39c021dfbaE8faC545936693aC917d5E7563);

    // Reward Tokens
    Comp private COMP = Comp(0xc00e94Cb662C3520282E6f5717214004A7f26888);
    ICompComptrollerPartial private CompController =
        ICompComptrollerPartial(0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B);

    address public collateralAddress;
    address public pool_address;
    address public ownerAddress;
    address public timelock_address;
    address public custodian_address;
    address public weth_address = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    uint256 public immutable missing_decimals;
    uint256 private constant PRICE_PRECISION = 1e6;

    // Max amount of collateral this contract can borrow from the ArthPool
    uint256 public borrow_cap = uint256(20000e6);

    // Amount the contract borrowed
    uint256 public borrowed_balance = 0;
    uint256 public borrowed_historical = 0;
    uint256 public paid_back_historical = 0;

    // Allowed strategies (can eventually be made into an array)
    bool public allow_yearn = true;
    bool public allow_aave = true;
    bool public allow_compound = true;

    /* ========== MODIFIERS ========== */

    modifier onlyByOwnerOrGovernance() {
        require(
            msg.sender == timelock_address || msg.sender == ownerAddress,
            'You are not the owner or the governance timelock'
        );
        _;
    }

    modifier onlyCustodian() {
        require(
            msg.sender == custodian_address,
            'You are not the rewards custodian'
        );
        _;
    }

    /* ========== CONSTRUCTOR ========== */

    constructor(
        address _arth_contract_address,
        address _arthx_contract_address,
        address _pool_address,
        address _collateralAddress,
        address _ownerAddress,
        address _custodian_address,
        address _timelock_address
    ) {
        ARTH = IARTH(_arth_contract_address);
        ARTHX = IARTHX(_arthx_contract_address);
        pool_address = _pool_address;
        pool = IARTHPool(_pool_address);
        collateralAddress = _collateralAddress;
        collateralToken = IERC20(_collateralAddress);
        timelock_address = _timelock_address;
        ownerAddress = _ownerAddress;
        custodian_address = _custodian_address;
        missing_decimals = uint256(18).sub(collateralToken.decimals());

        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }

    /* ========== VIEWS ========== */

    function showAllocations()
        external
        view
        returns (uint256[5] memory allocations)
    {
        // IMPORTANT
        // Should ONLY be used externally, because it may fail if any one of the functions below fail

        // All numbers given are assuming xyzUSDC, etc. is converted back to actual USDC
        allocations[0] = collateralToken.balanceOf(address(this)); // Unallocated
        allocations[1] = (yUSDC_V2.balanceOf(address(this)))
            .mul(yUSDC_V2.pricePerShare())
            .div(1e6); // yearn
        allocations[2] = aaveUSDC_Token.balanceOf(address(this)); // AAVE
        allocations[3] = (
            cUSDC.balanceOf(address(this)).mul(cUSDC.exchangeRateStored()).div(
                1e18
            )
        ); // Compound. Note that cUSDC is E8

        uint256 sum_tally = 0;
        for (uint256 i = 1; i < 5; i++) {
            if (allocations[i] > 0) {
                sum_tally = sum_tally.add(allocations[i]);
            }
        }

        allocations[4] = sum_tally; // Total Staked
    }

    function showRewards() external view returns (uint256[1] memory rewards) {
        // IMPORTANT
        // Should ONLY be used externally, because it may fail if COMP.balanceOf() fails
        rewards[0] = COMP.balanceOf(address(this)); // COMP
    }

    /* ========== PUBLIC FUNCTIONS ========== */

    // Needed for the Arth contract to function
    function getCollateralGMUBalance() external view returns (uint256) {
        // Needs to mimic the ArthPool value and return in E18
        // Only thing different should be borrowed_balance vs balanceOf()
        if (pool.collateralPricePaused() == true) {
            return
                borrowed_balance
                    .mul(10**missing_decimals)
                    .mul(pool.pausedPrice())
                    .div(PRICE_PRECISION);
        } else {
            uint256 eth_usd_price = controller.getETHGMUPrice();
            uint256 eth_collat_price =
                UniswapPairOracle(pool.collateralETHOracleAddress()).consult(
                    weth_address,
                    (PRICE_PRECISION * (10**missing_decimals))
                );

            uint256 collat_usd_price =
                eth_usd_price.mul(PRICE_PRECISION).div(eth_collat_price);
            return
                borrowed_balance
                    .mul(10**missing_decimals)
                    .mul(collat_usd_price)
                    .div(PRICE_PRECISION); //.mul(getCollateralPrice()).div(1e6);
        }
    }

    // This is basically a workaround to transfer USDC from the ArthPool to this investor contract
    // This contract is essentially marked as a 'pool' so it can call OnlyPools functions like poolMint and poolBurnFrom
    // on the main ARTH contract
    // It mints ARTH from nothing, and redeems it on the target pool for collateral and ARTHX.
    // The burn can be called separately later on
    function mintRedeemPart1(uint256 arth_amount)
        public
        onlyByOwnerOrGovernance
    {
        require(
            allow_yearn || allow_aave || allow_compound,
            'All strategies are currently off'
        );
        uint256 redemptionFee = pool.redemptionFee();
        uint256 col_price_usd = pool.getCollateralPrice();
        uint256 globalCollateralRatio = controller.getGlobalCollateralRatio();
        uint256 redeem_amount_E6 =
            (arth_amount.mul(uint256(1e6).sub(redemptionFee))).div(1e6).div(
                10**missing_decimals
            );
        uint256 expected_collat_amount =
            redeem_amount_E6.mul(globalCollateralRatio).div(1e6);
        expected_collat_amount = expected_collat_amount.mul(1e6).div(
            col_price_usd
        );

        require(
            borrowed_balance.add(expected_collat_amount) <= borrow_cap,
            'Borrow cap reached'
        );
        borrowed_balance = borrowed_balance.add(expected_collat_amount);
        borrowed_historical = borrowed_historical.add(expected_collat_amount);

        // Mint the arth
        ARTH.poolMint(address(this), arth_amount);

        // Redeem the arth
        ARTH.approve(address(pool), arth_amount);
        pool.redeemFractionalARTH(arth_amount, 0, 0);
    }

    function mintRedeemPart2() public onlyByOwnerOrGovernance {
        pool.collectRedemption();
    }

    function giveCollatBack(uint256 amount) public onlyByOwnerOrGovernance {
        // Still paying back principal
        if (amount <= borrowed_balance) {
            borrowed_balance = borrowed_balance.sub(amount);
        }
        // Pure profits
        else {
            borrowed_balance = 0;
        }
        paid_back_historical = paid_back_historical.add(amount);
        collateralToken.transfer(address(pool), amount);
    }

    function burnARTHX(uint256 amount) public onlyByOwnerOrGovernance {
        ARTHX.approve(address(this), amount);
        ARTHX.poolBurnFrom(address(this), amount);
    }

    /* ========== yearn V2 ========== */

    function yDepositUSDC(uint256 USDC_amount) public onlyByOwnerOrGovernance {
        require(allow_yearn, 'yearn strategy is currently off');
        collateralToken.approve(address(yUSDC_V2), USDC_amount);
        yUSDC_V2.deposit(USDC_amount);
    }

    // E6
    function yWithdrawUSDC(uint256 yUSDC_amount)
        public
        onlyByOwnerOrGovernance
    {
        yUSDC_V2.withdraw(yUSDC_amount);
    }

    /* ========== AAVE V2 ========== */

    function aaveDepositUSDC(uint256 USDC_amount)
        public
        onlyByOwnerOrGovernance
    {
        require(allow_aave, 'AAVE strategy is currently off');
        collateralToken.approve(address(aaveUSDC_Pool), USDC_amount);
        aaveUSDC_Pool.deposit(collateralAddress, USDC_amount, address(this), 0);
    }

    // E6
    function aaveWithdrawUSDC(uint256 aUSDC_amount)
        public
        onlyByOwnerOrGovernance
    {
        aaveUSDC_Pool.withdraw(collateralAddress, aUSDC_amount, address(this));
    }

    /* ========== Compound cUSDC + COMP ========== */

    function compoundMint_cUSDC(uint256 USDC_amount)
        public
        onlyByOwnerOrGovernance
    {
        require(allow_compound, 'Compound strategy is currently off');
        collateralToken.approve(address(cUSDC), USDC_amount);
        cUSDC.mint(USDC_amount);
    }

    // E8
    function compoundRedeem_cUSDC(uint256 cUSDC_amount)
        public
        onlyByOwnerOrGovernance
    {
        // NOTE that cUSDC is E8, NOT E6
        cUSDC.redeem(cUSDC_amount);
    }

    function compoundCollectCOMP() public onlyByOwnerOrGovernance {
        address[] memory cTokens = new address[](1);
        cTokens[0] = address(cUSDC);
        CompController.claimComp(address(this), cTokens);

        // CompController.claimComp(address(this), );
    }

    /* ========== Custodian ========== */

    function withdrawRewards() public onlyCustodian {
        COMP.transfer(custodian_address, COMP.balanceOf(address(this)));
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function setTimelock(address new_timelock)
        external
        onlyByOwnerOrGovernance
    {
        timelock_address = new_timelock;
    }

    function setOwner(address _ownerAddress) external onlyByOwnerOrGovernance {
        ownerAddress = _ownerAddress;
    }

    function setWethAddress(address _weth_address)
        external
        onlyByOwnerOrGovernance
    {
        weth_address = _weth_address;
    }

    function setMiscRewardsCustodian(address _custodian_address)
        external
        onlyByOwnerOrGovernance
    {
        custodian_address = _custodian_address;
    }

    function setPool(address _pool_address) external onlyByOwnerOrGovernance {
        pool_address = _pool_address;
        pool = IARTHPool(_pool_address);
    }

    function setBorrowCap(uint256 _borrow_cap)
        external
        onlyByOwnerOrGovernance
    {
        borrow_cap = _borrow_cap;
    }

    function setAllowedStrategies(
        bool _yearn,
        bool _aave,
        bool _compound
    ) external onlyByOwnerOrGovernance {
        allow_yearn = _yearn;
        allow_aave = _aave;
        allow_compound = _compound;
    }

    function emergencyRecoverERC20(address tokenAddress, uint256 tokenAmount)
        external
        onlyByOwnerOrGovernance
    {
        // Can only be triggered by owner or governance, not custodian
        // Tokens are sent to the custodian, as a sort of safeguard

        IERC20(tokenAddress).transfer(custodian_address, tokenAmount);
        emit Recovered(tokenAddress, tokenAmount);
    }

    /* ========== EVENTS ========== */

    event Recovered(address token, uint256 amount);
}
