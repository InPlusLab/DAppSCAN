pragma solidity 0.5.14;

import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "../config/GlobalConfig.sol";
import "../lib/Utils.sol";

/**
 * @dev Token Info Registry to manage Token information
 *      The Owner of the contract allowed to update the information
 */
contract TokenRegistry is Ownable {

    using SafeMath for uint256;

    /**
     * @dev TokenInfo struct stores Token Information, this includes:
     *      ERC20 Token address, Compound Token address, ChainLink Aggregator address etc.
     * @notice This struct will consume 5 storage locations
     */
    struct TokenInfo {
        // Token index, can store upto 255
        uint8 index;
        // ERC20 Token decimal
        uint8 decimals;
        // If token is enabled / disabled
        bool enabled;
        // Is ERC20 token charge transfer fee?
        bool isTransferFeeEnabled;
        // Is Token supported on Compound
        bool isSupportedOnCompound;
        // cToken address on Compound
        address cToken;
        // Chain Link Aggregator address for TOKEN/ETH pair
        address chainLinkOracle;
        // Borrow LTV, by default 60%
        uint256 borrowLTV;
    }

    event TokenAdded(address indexed token);
    event TokenUpdated(address indexed token);

    uint256 public constant MAX_TOKENS = 128;
    uint256 public constant SCALE = 100;

    // TokenAddress to TokenInfo mapping
    mapping (address => TokenInfo) public tokenInfo;

    // TokenAddress array
    address[] public tokens;
    GlobalConfig public globalConfig;

    /**
     */
    modifier whenTokenExists(address _token) {
        require(isTokenExist(_token), "Token not exists");
        _;
    }

    /**
     *  initializes the symbols structure
     */
    function initialize(GlobalConfig _globalConfig) public onlyOwner{
        globalConfig = _globalConfig;
    }

    /**
     * @dev Add a new token to registry
     * @param _token ERC20 Token address
     * @param _decimals Token's decimals
     * @param _isTransferFeeEnabled Is token changes transfer fee
     * @param _isSupportedOnCompound Is token supported on Compound
     * @param _cToken cToken contract address
     * @param _chainLinkOracle Chain Link Aggregator address to get TOKEN/ETH rate
     */
    function addToken(
        address _token,
        uint8 _decimals,
        bool _isTransferFeeEnabled,
        bool _isSupportedOnCompound,
        address _cToken,
        address _chainLinkOracle
    )
        public
        onlyOwner
    {
        require(_token != address(0), "Token address is zero");
        require(!isTokenExist(_token), "Token already exist");
        require(_chainLinkOracle != address(0), "ChainLinkAggregator address is zero");
        require(tokens.length < MAX_TOKENS, "Max token limit reached");

        TokenInfo storage storageTokenInfo = tokenInfo[_token];
        storageTokenInfo.index = uint8(tokens.length);
        storageTokenInfo.decimals = _decimals;
        storageTokenInfo.enabled = true;
        storageTokenInfo.isTransferFeeEnabled = _isTransferFeeEnabled;
        storageTokenInfo.isSupportedOnCompound = _isSupportedOnCompound;
        storageTokenInfo.cToken = _cToken;
        storageTokenInfo.chainLinkOracle = _chainLinkOracle;
        // Default values
        storageTokenInfo.borrowLTV = 60; //6e7; // 60%

        tokens.push(_token);
        emit TokenAdded(_token);
    }

    function updateBorrowLTV(
        address _token,
        uint256 _borrowLTV
    )
        external
        onlyOwner
        whenTokenExists(_token)
    {
        if (tokenInfo[_token].borrowLTV == _borrowLTV)
            return;

        // require(_borrowLTV != 0, "Borrow LTV is zero");
        require(_borrowLTV < SCALE, "Borrow LTV must be less than Scale");
        // require(liquidationThreshold > _borrowLTV, "Liquidation threshold must be greater than Borrow LTV");

        tokenInfo[_token].borrowLTV = _borrowLTV;
        emit TokenUpdated(_token);
    }

    /**
     */
    function updateTokenTransferFeeFlag(
        address _token,
        bool _isTransfeFeeEnabled
    )
        external
        onlyOwner
        whenTokenExists(_token)
    {
        if (tokenInfo[_token].isTransferFeeEnabled == _isTransfeFeeEnabled)
            return;

        tokenInfo[_token].isTransferFeeEnabled = _isTransfeFeeEnabled;
        emit TokenUpdated(_token);
    }

    /**
     */
    function updateTokenSupportedOnCompoundFlag(
        address _token,
        bool _isSupportedOnCompound
    )
        external
        onlyOwner
        whenTokenExists(_token)
    {
        if (tokenInfo[_token].isSupportedOnCompound == _isSupportedOnCompound)
            return;

        tokenInfo[_token].isSupportedOnCompound = _isSupportedOnCompound;
        emit TokenUpdated(_token);
    }

    /**
     */
    function updateCToken(
        address _token,
        address _cToken
    )
        external
        onlyOwner
        whenTokenExists(_token)
    {
        if (tokenInfo[_token].cToken == _cToken)
            return;

        tokenInfo[_token].cToken = _cToken;
        emit TokenUpdated(_token);
    }

    /**
     */
    function updateChainLinkAggregator(
        address _token,
        address _chainLinkOracle
    )
        external
        onlyOwner
        whenTokenExists(_token)
    {
        if (tokenInfo[_token].chainLinkOracle == _chainLinkOracle)
            return;

        tokenInfo[_token].chainLinkOracle = _chainLinkOracle;
        emit TokenUpdated(_token);
    }


    function enableToken(address _token) external onlyOwner whenTokenExists(_token) {
        require(!tokenInfo[_token].enabled, "Token already enabled");

        tokenInfo[_token].enabled = true;

        emit TokenUpdated(_token);
    }

    function disableToken(address _token) external onlyOwner whenTokenExists(_token) {
        require(tokenInfo[_token].enabled, "Token already disabled");

        tokenInfo[_token].enabled = false;

        emit TokenUpdated(_token);
    }

    // =====================
    //      GETTERS
    // =====================

    /**
     * @dev Is token address is registered
     * @param _token token address
     * @return Returns `true` when token registered, otherwise `false`
     */
    function isTokenExist(address _token) public view returns (bool isExist) {
        isExist = tokenInfo[_token].chainLinkOracle != address(0);
    }

    function getTokens() external view returns (address[] memory) {
        return tokens;
    }

    function getTokenIndex(address _token) external view returns (uint8) {
        return tokenInfo[_token].index;
    }

    function isTokenEnabled(address _token) external view returns (bool) {
        return tokenInfo[_token].enabled;
    }

    /**
     */
    function getCTokens() external view returns (address[] memory cTokens) {
        uint256 len = tokens.length;
        cTokens = new address[](len);
        for(uint256 i = 0; i < len; i++) {
            cTokens[i] = tokenInfo[tokens[i]].cToken;
        }
    }

    function getTokenDecimals(address _token) public view returns (uint8) {
        return tokenInfo[_token].decimals;
    }

    function isTransferFeeEnabled(address _token) external view returns (bool) {
        return tokenInfo[_token].isTransferFeeEnabled;
    }

    function isSupportedOnCompound(address _token) external view returns (bool) {
        return tokenInfo[_token].isSupportedOnCompound;
    }

    /**
     */
    function getCToken(address _token) external view returns (address) {
        return tokenInfo[_token].cToken;
    }

    function getChainLinkAggregator(address _token) external view returns (address) {
        return tokenInfo[_token].chainLinkOracle;
    }

    function getBorrowLTV(address _token) external view returns (uint256) {
        return tokenInfo[_token].borrowLTV;
    }

    function getCoinLength() public view returns (uint256 length) {
        return tokens.length;
    }

    function addressFromIndex(uint index) public view returns(address) {
        require(index < tokens.length, "coinIndex must be smaller than the coins length.");
        return tokens[index];
    }

    function priceFromIndex(uint index) public view returns(uint256) {
        require(index < tokens.length, "coinIndex must be smaller than the coins length.");
        address tokenAddress = tokens[index];
        // Temp fix
        if(Utils._isETH(address(globalConfig), tokenAddress)) {
            return 1e18;
        }
        return uint256(globalConfig.chainLink().getLatestAnswer(tokenAddress));
    }

    function priceFromAddress(address tokenAddress) public view returns(uint256) {
        if(Utils._isETH(address(globalConfig), tokenAddress)) {
            return 1e18;
        }
        return uint256(globalConfig.chainLink().getLatestAnswer(tokenAddress));
    }

    // function _isETH(address _token) public view returns (bool) {
    //     return globalConfig.constants().ETH_ADDR() == _token;
    // }

    // function getDivisor(address _token) public view returns (uint256) {
    //     if(_isETH(_token)) return INT_UNIT;
    //     return 10 ** uint256(getTokenDecimals(_token));
    // }

    mapping(address => uint) public depositeMiningSpeeds;
    mapping(address => uint) public borrowMiningSpeeds;

    function updateMiningSpeed(address _token, uint _depositeMiningSpeed, uint _borrowMiningSpeed) public onlyOwner{
        if(_depositeMiningSpeed != depositeMiningSpeeds[_token]) {
            depositeMiningSpeeds[_token] = _depositeMiningSpeed;
        }
        
        if(_borrowMiningSpeed != borrowMiningSpeeds[_token]) {
            borrowMiningSpeeds[_token] = _borrowMiningSpeed;
        }

        emit TokenUpdated(_token);
    }
}