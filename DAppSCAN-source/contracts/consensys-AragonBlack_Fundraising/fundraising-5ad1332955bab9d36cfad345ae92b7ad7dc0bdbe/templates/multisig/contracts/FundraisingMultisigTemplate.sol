pragma solidity 0.4.24;

import "@aragon/os/contracts/common/EtherTokenConstant.sol";
import "@aragon/os/contracts/lib/token/ERC20.sol";
import "@aragon/templates-shared/contracts/BaseTemplate.sol";
import "@aragon/apps-agent/contracts/Agent.sol";
import "@ablack/fundraising-bancor-formula/contracts/BancorFormula.sol";
import {AragonFundraisingController as Controller} from "@ablack/fundraising-aragon-fundraising/contracts/AragonFundraisingController.sol";
import {BatchedBancorMarketMaker as MarketMaker} from "@ablack/fundraising-batched-bancor-market-maker/contracts/BatchedBancorMarketMaker.sol";
import "@ablack/fundraising-presale/contracts/Presale.sol";
import "@ablack/fundraising-tap/contracts/Tap.sol";


contract FundraisingMultisigTemplate is EtherTokenConstant, BaseTemplate {
    string    private constant ERROR_BAD_SETTINGS     = "FM_BAD_SETTINGS";
    string    private constant ERROR_MISSING_CACHE    = "FM_MISSING_CACHE";

    bool      private constant BOARD_TRANSFERABLE     = false;
    uint8     private constant BOARD_TOKEN_DECIMALS   = uint8(0);
    uint256   private constant BOARD_MAX_PER_ACCOUNT  = uint256(1);

    bool      private constant SHARE_TRANSFERABLE     = true;
    uint8     private constant SHARE_TOKEN_DECIMALS   = uint8(18);
    uint256   private constant SHARE_MAX_PER_ACCOUNT  = uint256(0);

    uint64    private constant DEFAULT_FINANCE_PERIOD = uint64(30 days);

    uint256   private constant BUY_FEE_PCT            = 0;
    uint256   private constant SELL_FEE_PCT           = 0;

    uint32    private constant DAI_RESERVE_RATIO      = 100000; // 10%
    uint32    private constant ANT_RESERVE_RATIO      = 10000;  // 1%

    bytes32   private constant BANCOR_FORMULA_ID      = 0xd71dde5e4bea1928026c1779bde7ed27bd7ef3d0ce9802e4117631eb6fa4ed7d;
    bytes32   private constant PRESALE_ID             = 0x5de9bbdeaf6584c220c7b7f1922383bcd8bbcd4b48832080afd9d5ebf9a04df5;
    bytes32   private constant MARKET_MAKER_ID        = 0xc2bb88ab974c474221f15f691ed9da38be2f5d37364180cec05403c656981bf0;
    bytes32   private constant ARAGON_FUNDRAISING_ID  = 0x668ac370eed7e5861234d1c0a1e512686f53594fcb887e5bcecc35675a4becac;
    bytes32   private constant TAP_ID                 = 0x82967efab7144b764bc9bca2f31a721269b6618c0ff4e50545737700a5e9c9dc;

    struct Cache {
        address dao;
        address boardTokenManager;
        address boardVoting;
        address vault;
        address finance;
        address shareVoting;
        address shareTokenManager;
        address reserve;
        address presale;
        address marketMaker;
        address tap;
        address controller;
    }

    address[] public collaterals;
    mapping (address => Cache) private cache;

    constructor(
        DAOFactory              _daoFactory,
        ENS                     _ens,
        MiniMeTokenFactory      _miniMeFactory,
        IFIFSResolvingRegistrar _aragonID,
        address                 _dai,
        address                 _ant
    )
        BaseTemplate(_daoFactory, _ens, _miniMeFactory, _aragonID)
        public
    {
        _ensureAragonIdIsValid(_aragonID);
        _ensureMiniMeFactoryIsValid(_miniMeFactory);
        _ensureTokenIsContractOrETH(_dai);
        _ensureTokenIsContractOrETH(_ant);

        collaterals.push(address(_dai));
        collaterals.push(address(_ant));
    }

    /***** external functions *****/

    function prepareInstance(
        string    _boardTokenName,
        string    _boardTokenSymbol,
        address[] _boardMembers,
        uint64[3] _boardVotingSettings,
        uint64    _financePeriod
    )
        external
    {
        require(_boardMembers.length > 0,         ERROR_BAD_SETTINGS);
        require(_boardVotingSettings.length == 3, ERROR_BAD_SETTINGS);

        // deploy DAO
        (Kernel dao, ACL acl) = _createDAO();
        // deploy board token
        MiniMeToken boardToken = _createToken(_boardTokenName, _boardTokenSymbol, BOARD_TOKEN_DECIMALS);
        // install board apps
        TokenManager tm = _installBoardApps(dao, boardToken, _boardVotingSettings, _financePeriod);
        // mint board tokens
        _mintTokens(acl, tm, _boardMembers, 1);
        // cache DAO
        _cacheDao(dao);
    }

    function installShareApps(
        string    _shareTokenName,
        string    _shareTokenSymbol,
        uint64[3] _shareVotingSettings
    )
        external
    {
        require(_shareVotingSettings.length == 3, ERROR_BAD_SETTINGS);
        _ensureBoardAppsCache();

        Kernel dao = _daoCache();
        // deploy share token
        MiniMeToken shareToken = _createToken(_shareTokenName, _shareTokenSymbol, SHARE_TOKEN_DECIMALS);
        // install share apps
        _installShareApps(dao, shareToken, _shareVotingSettings);
        // setup board apps permissions [now that share apps have been installed]
        _setupBoardPermissions(dao);
    }

    function installFundraisingApps(
        uint256 _goal,
        uint64  _period,
        uint256 _exchangeRate,
        uint64  _vestingCliffPeriod,
        uint64  _vestingCompletePeriod,
        uint256 _supplyOfferedPct,
        uint256 _fundingForBeneficiaryPct,
        uint64  _openDate,
        uint256 _batchBlocks,
        uint256 _maxTapRateIncreasePct,
        uint256 _maxTapFloorDecreasePct
    )
        external
    {
        _ensureShareAppsCache();

        Kernel dao = _daoCache();
        // install fundraising apps
        _installFundraisingApps(
            dao,
            _goal,
            _period,
            _exchangeRate,
            _vestingCliffPeriod,
            _vestingCompletePeriod,
            _supplyOfferedPct,
            _fundingForBeneficiaryPct,
            _openDate,
            _batchBlocks,
            _maxTapRateIncreasePct,
            _maxTapFloorDecreasePct
        );
        // setup share apps permissions [now that fundraising apps have been installed]
        _setupSharePermissions(dao);
        // setup fundraising apps permissions
        _setupFundraisingPermissions(dao);
    }

    function finalizeInstance(
        string     _id,
        uint256[2] _virtualSupplies,
        uint256[2] _virtualBalances,
        uint256[2] _slippages,
        uint256    _rateDAI,
        uint256    _floorDAI
    )
        external
    {
        require(bytes(_id).length > 0,        ERROR_BAD_SETTINGS);
        require(_virtualSupplies.length == 2, ERROR_BAD_SETTINGS);
        require(_virtualBalances.length == 2, ERROR_BAD_SETTINGS);
        require(_slippages.length == 2,       ERROR_BAD_SETTINGS);
        _ensureFundraisingAppsCache();

        Kernel dao = _daoCache();
        ACL acl = ACL(dao.acl());
        (, Voting shareVoting) = _shareAppsCache();

        // setup collaterals
        _setupCollaterals(dao, _virtualSupplies, _virtualBalances, _slippages, _rateDAI, _floorDAI);
        // setup EVM script registry permissions
        _createEvmScriptsRegistryPermissions(acl, shareVoting, shareVoting);
        // clear DAO permissions
        _transferRootPermissionsFromTemplateAndFinalizeDAO(dao, shareVoting, shareVoting);
        // register id
        _registerID(_id, address(dao));
        // clear cache
        _clearCache();
    }

    /***** internal apps installation functions *****/

    function _installBoardApps(Kernel _dao, MiniMeToken _token, uint64[3] _votingSettings, uint64 _financePeriod)
        internal
        returns (TokenManager)
    {
        TokenManager tm = _installTokenManagerApp(_dao, _token, BOARD_TRANSFERABLE, BOARD_MAX_PER_ACCOUNT);
        Voting voting = _installVotingApp(_dao, _token, _votingSettings);
        Vault vault = _installVaultApp(_dao);
        Finance finance = _installFinanceApp(_dao, vault, _financePeriod == 0 ? DEFAULT_FINANCE_PERIOD : _financePeriod);

        _cacheBoardApps(tm, voting, vault, finance);

        return tm;
    }

    function _installShareApps(Kernel _dao, MiniMeToken _shareToken, uint64[3] _shareVotingSettings)
        internal
    {
        TokenManager tm = _installTokenManagerApp(_dao, _shareToken, SHARE_TRANSFERABLE, SHARE_MAX_PER_ACCOUNT);
        Voting voting = _installVotingApp(_dao, _shareToken, _shareVotingSettings);

        _cacheShareApps(tm, voting);
    }

    function _installFundraisingApps(
        Kernel  _dao,
        uint256 _goal,
        uint64  _period,
        uint256 _exchangeRate,
        uint64  _vestingCliffPeriod,
        uint64  _vestingCompletePeriod,
        uint256 _supplyOfferedPct,
        uint256 _fundingForBeneficiaryPct,
        uint64  _openDate,
        uint256 _batchBlocks,
        uint256 _maxTapRateIncreasePct,
        uint256 _maxTapFloorDecreasePct
    )
        internal
    {
        _proxifyFundraisingApps(_dao);

        _initializePresale(
            _goal,
            _period,
            _exchangeRate,
            _vestingCliffPeriod,
            _vestingCompletePeriod,
            _supplyOfferedPct,
            _fundingForBeneficiaryPct,
            _openDate
        );
        _initializeMarketMaker(_batchBlocks);
        _initializeTap(_batchBlocks, _maxTapRateIncreasePct, _maxTapFloorDecreasePct);
        _initializeController();
    }

    function _proxifyFundraisingApps(Kernel _dao) internal {
        Agent reserve = _installNonDefaultAgentApp(_dao);
        Presale presale = Presale(_registerApp(_dao, PRESALE_ID));
        MarketMaker marketMaker = MarketMaker(_registerApp(_dao, MARKET_MAKER_ID));
        Tap tap = Tap(_registerApp(_dao, TAP_ID));
        Controller controller = Controller(_registerApp(_dao, ARAGON_FUNDRAISING_ID));

        _cacheFundraisingApps(reserve, presale, marketMaker, tap, controller);
    }

    /***** internal apps initialization functions *****/

    function _initializePresale(
        uint256 _goal,
        uint64  _period,
        uint256 _exchangeRate,
        uint64  _vestingCliffPeriod,
        uint64  _vestingCompletePeriod,
        uint256 _supplyOfferedPct,
        uint256 _fundingForBeneficiaryPct,
        uint64  _openDate
    )
        internal
    {
        _presaleCache().initialize(
            _controllerCache(),
            _shareTMCache(),
            _reserveCache(),
            _vaultCache(),
            collaterals[0],
            _goal,
            _period,
            _exchangeRate,
            _vestingCliffPeriod,
            _vestingCompletePeriod,
            _supplyOfferedPct,
            _fundingForBeneficiaryPct,
            _openDate
        );
    }

    function _initializeMarketMaker(uint256 _batchBlocks) internal {
        IBancorFormula bancorFormula = IBancorFormula(_latestVersionAppBase(BANCOR_FORMULA_ID));

        (,, Vault beneficiary,) = _boardAppsCache();
        (TokenManager shareTM,) = _shareAppsCache();
        (Agent reserve,, MarketMaker marketMaker,, Controller controller) = _fundraisingAppsCache();

        marketMaker.initialize(controller, shareTM, bancorFormula, reserve, beneficiary, _batchBlocks, BUY_FEE_PCT, SELL_FEE_PCT);
    }

    function _initializeTap(uint256 _batchBlocks, uint256 _maxTapRateIncreasePct, uint256 _maxTapFloorDecreasePct) internal {
        (,, Vault beneficiary,) = _boardAppsCache();
        (Agent reserve,,, Tap tap, Controller controller) = _fundraisingAppsCache();

        tap.initialize(controller, reserve, beneficiary, _batchBlocks, _maxTapRateIncreasePct, _maxTapFloorDecreasePct);
    }

    function _initializeController() internal {
        (Agent reserve, Presale presale, MarketMaker marketMaker, Tap tap, Controller controller) = _fundraisingAppsCache();
        address[] memory toReset = new address[](1);
        toReset[0] = collaterals[0];
        controller.initialize(presale, marketMaker, reserve, tap, toReset);
    }

    /***** internal setup functions *****/

    function _setupCollaterals(
        Kernel     _dao,
        uint256[2] _virtualSupplies,
        uint256[2] _virtualBalances,
        uint256[2] _slippages,
        uint256    _rateDAI,
        uint256    _floorDAI
    )
        internal
    {
        ACL acl = ACL(_dao.acl());
        (, Voting shareVoting) = _shareAppsCache();
        (,,,, Controller controller) = _fundraisingAppsCache();

        // create and grant ADD_PROTECTED_TOKEN_ROLE to this template
        // SWC-108-State Variable Default Visibility: L335
        acl.createPermission(this, controller, controller.ADD_COLLATERAL_TOKEN_ROLE(), this);
        // add DAI both as a protected collateral and a tapped token
        controller.addCollateralToken(
            collaterals[0],
            _virtualSupplies[0],
            _virtualBalances[0],
            DAI_RESERVE_RATIO,
            _slippages[0],
            _rateDAI,
            _floorDAI
        );
        // add ANT as a protected collateral [but not as a tapped token]
        controller.addCollateralToken(
            collaterals[1],
            _virtualSupplies[1],
            _virtualBalances[1],
            ANT_RESERVE_RATIO,
            _slippages[1],
            0,
            0
        );
        // transfer ADD_PROTECTED_TOKEN_ROLE
        _transferPermissionFromTemplate(acl, controller, shareVoting, controller.ADD_COLLATERAL_TOKEN_ROLE(), shareVoting);
    }

    /***** internal permissions functions *****/

    function _setupBoardPermissions(Kernel _dao) internal {
        ACL acl = ACL(_dao.acl());

        (TokenManager boardTM, Voting boardVoting, Vault vault, Finance finance) = _boardAppsCache();
        (, Voting shareVoting) = _shareAppsCache();

        // token manager
        _createTokenManagerPermissions(acl, boardTM, boardVoting, shareVoting);
        // voting
        _createVotingPermissions(acl, boardVoting, boardVoting, boardTM, shareVoting);
        // vault
        _createVaultPermissions(acl, vault, finance, shareVoting);
        // finance
        _createFinancePermissions(acl, finance, boardVoting, shareVoting);
        _createFinanceCreatePaymentsPermission(acl, finance, boardVoting, shareVoting);
    }

    function _setupSharePermissions(Kernel _dao) internal {
        ACL acl = ACL(_dao.acl());

        (TokenManager boardTM,,,) = _boardAppsCache();
        (TokenManager shareTM, Voting shareVoting) = _shareAppsCache();
        (, Presale presale, MarketMaker marketMaker,,) = _fundraisingAppsCache();

        // token manager
        address[] memory grantees = new address[](2);
        grantees[0] = address(marketMaker);
        grantees[1] = address(presale);
        acl.createPermission(marketMaker, shareTM, shareTM.MINT_ROLE(),shareVoting);
        acl.createPermission(presale, shareTM, shareTM.ISSUE_ROLE(),shareVoting);
        acl.createPermission(presale, shareTM, shareTM.ASSIGN_ROLE(),shareVoting);
        acl.createPermission(presale, shareTM, shareTM.REVOKE_VESTINGS_ROLE(), shareVoting);
        _createPermissions(acl, grantees, shareTM, shareTM.BURN_ROLE(), shareVoting);
        // voting
        _createVotingPermissions(acl, shareVoting, shareVoting, boardTM, shareVoting);
    }

    function _setupFundraisingPermissions(Kernel _dao) internal {
        ACL acl = ACL(_dao.acl());

        (, Voting boardVoting,,) = _boardAppsCache();
        (, Voting shareVoting) = _shareAppsCache();
        (Agent reserve, Presale presale, MarketMaker marketMaker, Tap tap, Controller controller) = _fundraisingAppsCache();

        // reserve
        address[] memory grantees = new address[](2);
        grantees[0] = address(tap);
        grantees[1] = address(marketMaker);
        acl.createPermission(shareVoting, reserve, reserve.SAFE_EXECUTE_ROLE(), shareVoting);
        acl.createPermission(controller, reserve, reserve.ADD_PROTECTED_TOKEN_ROLE(), shareVoting);
        _createPermissions(acl, grantees, reserve, reserve.TRANSFER_ROLE(), shareVoting);
        // presale
        acl.createPermission(controller, presale, presale.OPEN_ROLE(), shareVoting);
        acl.createPermission(controller, presale, presale.CONTRIBUTE_ROLE(), shareVoting);
        // market maker
        acl.createPermission(controller, marketMaker, marketMaker.OPEN_ROLE(), shareVoting);
        acl.createPermission(controller, marketMaker, marketMaker.UPDATE_BENEFICIARY_ROLE(), shareVoting);
        acl.createPermission(controller, marketMaker, marketMaker.UPDATE_FEES_ROLE(), shareVoting);
        acl.createPermission(controller, marketMaker, marketMaker.ADD_COLLATERAL_TOKEN_ROLE(), shareVoting);
        acl.createPermission(controller, marketMaker, marketMaker.REMOVE_COLLATERAL_TOKEN_ROLE(), shareVoting);
        acl.createPermission(controller, marketMaker, marketMaker.UPDATE_COLLATERAL_TOKEN_ROLE(), shareVoting);
        acl.createPermission(controller, marketMaker, marketMaker.OPEN_BUY_ORDER_ROLE(), shareVoting);
        acl.createPermission(controller, marketMaker, marketMaker.OPEN_SELL_ORDER_ROLE(), shareVoting);
        // tap
        acl.createPermission(controller, tap, tap.UPDATE_BENEFICIARY_ROLE(), shareVoting);
        acl.createPermission(controller, tap, tap.UPDATE_MAXIMUM_TAP_RATE_INCREASE_PCT_ROLE(), shareVoting);
        acl.createPermission(controller, tap, tap.UPDATE_MAXIMUM_TAP_FLOOR_DECREASE_PCT_ROLE(), shareVoting);
        acl.createPermission(controller, tap, tap.ADD_TAPPED_TOKEN_ROLE(), shareVoting);
        acl.createPermission(controller, tap, tap.UPDATE_TAPPED_TOKEN_ROLE(), shareVoting);
        acl.createPermission(controller, tap, tap.RESET_TAPPED_TOKEN_ROLE(), shareVoting);
        acl.createPermission(controller, tap, tap.WITHDRAW_ROLE(), shareVoting);
        // controller
        // ADD_COLLATERAL_TOKEN_ROLE is handled later [after collaterals have been added]
        acl.createPermission(shareVoting, controller, controller.UPDATE_BENEFICIARY_ROLE(), shareVoting);
        acl.createPermission(shareVoting, controller, controller.UPDATE_FEES_ROLE(), shareVoting);
        // acl.createPermission(shareVoting, controller, controller.ADD_COLLATERAL_TOKEN_ROLE(), shareVoting);
        acl.createPermission(shareVoting, controller, controller.REMOVE_COLLATERAL_TOKEN_ROLE(), shareVoting);
        acl.createPermission(shareVoting, controller, controller.UPDATE_COLLATERAL_TOKEN_ROLE(), shareVoting);
        acl.createPermission(shareVoting, controller, controller.UPDATE_MAXIMUM_TAP_RATE_INCREASE_PCT_ROLE(), shareVoting);
        acl.createPermission(shareVoting, controller, controller.UPDATE_MAXIMUM_TAP_FLOOR_DECREASE_PCT_ROLE(), shareVoting);
        acl.createPermission(shareVoting, controller, controller.ADD_TOKEN_TAP_ROLE(), shareVoting);
        acl.createPermission(shareVoting, controller, controller.UPDATE_TOKEN_TAP_ROLE(), shareVoting);
        acl.createPermission(boardVoting, controller, controller.OPEN_PRESALE_ROLE(), shareVoting);
        acl.createPermission(presale, controller, controller.OPEN_TRADING_ROLE(), shareVoting);
        acl.createPermission(address(-1), controller, controller.CONTRIBUTE_ROLE(), shareVoting);
        acl.createPermission(address(-1), controller, controller.OPEN_BUY_ORDER_ROLE(), shareVoting);
        acl.createPermission(address(-1), controller, controller.OPEN_SELL_ORDER_ROLE(), shareVoting);
        acl.createPermission(address(-1), controller, controller.WITHDRAW_ROLE(), shareVoting);
    }

    /***** internal cache functions *****/

    function _cacheDao(Kernel _dao) internal {
        Cache storage c = cache[msg.sender];

        c.dao = address(_dao);
    }

    function _cacheBoardApps(TokenManager _boardTM, Voting _boardVoting, Vault _vault, Finance _finance) internal {
        Cache storage c = cache[msg.sender];

        c.boardTokenManager = address(_boardTM);
        c.boardVoting = address(_boardVoting);
        c.vault = address(_vault);
        c.finance = address(_finance);
    }

    function _cacheShareApps(TokenManager _shareTM, Voting _shareVoting) internal {
        Cache storage c = cache[msg.sender];

        c.shareTokenManager = address(_shareTM);
        c.shareVoting = address(_shareVoting);
    }

    function _cacheFundraisingApps(Agent _reserve, Presale _presale, MarketMaker _marketMaker, Tap _tap, Controller _controller) internal {
        Cache storage c = cache[msg.sender];

        c.reserve = address(_reserve);
        c.presale = address(_presale);
        c.marketMaker = address(_marketMaker);
        c.tap = address(_tap);
        c.controller = address(_controller);
    }

    function _daoCache() internal returns (Kernel dao) {
        Cache storage c = cache[msg.sender];

        dao = Kernel(c.dao);
    }

    function _boardAppsCache() internal returns (TokenManager boardTM, Voting boardVoting, Vault vault, Finance finance) {
        Cache storage c = cache[msg.sender];

        boardTM = TokenManager(c.boardTokenManager);
        boardVoting = Voting(c.boardVoting);
        vault = Vault(c.vault);
        finance = Finance(c.finance);
    }

    function _shareAppsCache() internal returns (TokenManager shareTM, Voting shareVoting) {
        Cache storage c = cache[msg.sender];

        shareTM = TokenManager(c.shareTokenManager);
        shareVoting = Voting(c.shareVoting);
    }

    function _fundraisingAppsCache() internal returns (Agent reserve, Presale presale, MarketMaker marketMaker, Tap tap, Controller controller) {
        Cache storage c = cache[msg.sender];

        reserve = Agent(c.reserve);
        presale = Presale(c.presale);
        marketMaker = MarketMaker(c.marketMaker);
        tap = Tap(c.tap);
        controller = Controller(c.controller);
    }

    function _clearCache() internal {
        Cache storage c = cache[msg.sender];

        delete c.dao;
        delete c.boardTokenManager;
        delete c.boardVoting;
        delete c.vault;
        delete c.finance;
        delete c.shareVoting;
        delete c.shareTokenManager;
        delete c.reserve;
        delete c.presale;
        delete c.marketMaker;
        delete c.tap;
        delete c.controller;
    }

    /**
     * NOTE
     * the following functions are only needed for the presale
     * initialization function [which we can't compile otherwise
     * because of a `stack too deep` error]
    */

    function _vaultCache() internal returns (Vault vault) {
        Cache storage c = cache[msg.sender];

        vault = Vault(c.vault);
    }

    function _shareTMCache() internal returns (TokenManager shareTM) {
        Cache storage c = cache[msg.sender];

        shareTM = TokenManager(c.shareTokenManager);
    }

    function _reserveCache() internal returns (Agent reserve) {
        Cache storage c = cache[msg.sender];

        reserve = Agent(c.reserve);
    }

    function _presaleCache() internal returns (Presale presale) {
        Cache storage c = cache[msg.sender];

        presale = Presale(c.presale);
    }

    function _controllerCache() internal returns (Controller controller) {
        Cache storage c = cache[msg.sender];

        controller = Controller(c.controller);
    }

    /***** internal check functions *****/

     function _ensureTokenIsContractOrETH(address _token) internal view returns (bool) {
        require(isContract(_token) || _token == ETH, ERROR_BAD_SETTINGS);
    }

    function _ensureBoardAppsCache() internal {
        Cache storage c = cache[msg.sender];
        require(
            c.boardTokenManager != address(0) &&
            c.boardVoting != address(0) &&
            c.vault != address(0) &&
            c.finance != address(0),
            ERROR_MISSING_CACHE
        );
    }

    function _ensureShareAppsCache() internal {
        Cache storage c = cache[msg.sender];
        require(
            c.shareTokenManager != address(0) &&
            c.shareVoting != address(0),
            ERROR_MISSING_CACHE
        );
    }

    function _ensureFundraisingAppsCache() internal {
        Cache storage c = cache[msg.sender];
        require(
            c.reserve != address(0) &&
            c.presale != address(0) &&
            c.marketMaker != address(0) &&
            c.tap != address(0) &&
            c.controller != address(0),
            ERROR_MISSING_CACHE
        );
    }

    /***** internal utils functions *****/

    function _registerApp(Kernel _dao, bytes32 _appId) internal returns (address) {
        address proxy = _dao.newAppInstance(_appId, _latestVersionAppBase(_appId));

        emit InstalledApp(proxy, _appId);

        return proxy;
    }
}
