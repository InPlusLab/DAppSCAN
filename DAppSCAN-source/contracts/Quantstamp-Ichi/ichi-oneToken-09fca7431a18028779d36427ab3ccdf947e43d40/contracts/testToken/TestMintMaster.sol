// SPDX-License-Identifier: Unlicensed

pragma solidity 0.7.6;

import "../mintMaster/MintMasterCommon.sol";
import "../interface/IOneTokenV1.sol";
import "../interface/IOracle.sol";

/**
 * @notice Separate ownable instances can be managed by separate governing authorities.
 * Immutable windowSize and granularity changes require a new oracle contract. 
 */

contract TestMintMaster is MintMasterCommon {
    
    uint constant DEFAULT_RATIO = 10 ** 18; // 100%
    uint constant DEFAULT_STEP_SIZE = 0;
    uint constant MAX_VOLUME = 1000;

    struct Parameters {
        bool set;
        uint minRatio;
        uint maxRatio;
        uint stepSize;
        uint lastRatio;      
    }

    mapping(address => Parameters) public parameters;

    event Deployed(address sender, string description);
    event Initialized(address sender, address oneTokenOracle);
    event OneTokenOracleChanged(address sender, address oneToken, address oracle);
    event SetParams(address sender, address oneToken, uint minRatio, uint maxRatio, uint stepSize, uint initialRatio);
    event UpdateMintingRatio(address sender, uint volatility, uint newRatio, uint maxOrderVolume);
    event StepSizeSet(address sender, uint stepSize);
    event MinRatioSet(address sender, uint minRatio);
    event MaxRatioSet(address sender, uint maxRatio);
    event RatioSet(address sender, uint ratio);
   
    constructor(address oneTokenFactory_, string memory description_) 
        MintMasterCommon(oneTokenFactory_, description_)
    {
        emit Deployed(msg.sender, description_);
    }

    /**
     @notice initializes the common interface 
     @dev A single instance can be shared by n oneToken implementations. Initialize from each instance. 
     @param oneTokenOracle gets the exchange rate of the oneToken
     */
    function init(address oneTokenOracle) external override {
        _setParams(msg.sender, DEFAULT_RATIO, DEFAULT_RATIO, DEFAULT_STEP_SIZE, DEFAULT_RATIO);
        _initMintMaster(msg.sender, oneTokenOracle);
        emit Initialized(msg.sender, oneTokenOracle);
   
    }

    /**
     @notice changes the oracle used to assess the oneTokens' value in relation to the peg
     @dev may use the peggedOracle (efficient but not informative) or an active oracle 
     @param oneToken oneToken vault (also ERC20 token)
     @param oracle oracle contract must be registered in the factory
     */
    function changeOracle(address oneToken, address oracle) external onlyTokenOwner(oneToken) {
        _initMintMaster(oneToken, oracle);
        emit OneTokenOracleChanged(msg.sender, oneToken, oracle);
    }

    /**
     @notice updates parameters for a given oneToken that uses this module
     @dev inspects the oneToken implementation to establish authority
     @param oneToken token context for parameters
     @param minRatio minimum minting ratio that will be set
     @param maxRatio maximum minting ratio that will be set
     @param stepSize adjustment size iteration
     @param initialRatio unadjusted starting minting ratio
     */
    function setParams(
        address oneToken, 
        uint minRatio, 
        uint maxRatio, 
        uint stepSize, 
        uint initialRatio
    ) 
        external
        onlyTokenOwner(oneToken)
    {
        _setParams(oneToken, minRatio, maxRatio, stepSize, initialRatio);
    }

    function _setParams(
        address oneToken, 
        uint minRatio, 
        uint maxRatio, 
        uint stepSize, 
        uint initialRatio
    ) 
        private
    {
        Parameters storage p = parameters[oneToken];
        require(minRatio <= maxRatio, "Incremental: minRatio must be <= maxRatio");
        require(maxRatio <= PRECISION, "Incremental: maxRatio must be <= 10 ** 18");
        // Can be zero to prevent movement
        // require(stepSize > 0, "Incremental: stepSize must be > 0");
        require(stepSize < maxRatio - minRatio || stepSize == 0, "Incremental: stepSize must be < (max - min) or zero.");
        require(initialRatio >= minRatio, "Incremental: initial ratio must be >= min ratio.");
        require(initialRatio <= maxRatio, "Incremental: initial ratio must be <= max ratio.");
        p.minRatio = minRatio;
        p.maxRatio = maxRatio;
        p.stepSize = stepSize;
        p.lastRatio = initialRatio;
        p.set = true;
        emit SetParams(msg.sender, oneToken, minRatio, maxRatio, stepSize, initialRatio);
    }
 
    /**
     @notice returns an adjusted minting ratio
     @dev oneToken contracts call this to get their own minting ratio
     */
    function getMintingRatio(address /* collateralToken */) external view override returns(uint ratio, uint maxOrderVolume) {
        return getMintingRatio2(msg.sender, NULL_ADDRESS);
    }

    /**
     @notice returns an adjusted minting ratio. OneTokens use this function and it relies on initialization to select the oracle
     @dev anyone calls this to inspect any oneToken minting ratio
     @param oneToken oneToken implementation to inspect
     */    
    function getMintingRatio2(address oneToken, address /* collateralToken */) public view override returns(uint ratio, uint maxOrderValue) {
        address oracle = oneTokenOracles[oneToken];
        return getMintingRatio4(oneToken, oracle, NULL_ADDRESS, NULL_ADDRESS);
    }

    /**
     @notice returns an adjusted minting ratio
     @dev anyone calls this to inspect any oneToken minting ratio
     @param oneToken oneToken implementation to inspect
     @param oneTokenOracle explicit oracle selection
     */   
    function getMintingRatio4(address oneToken, address oneTokenOracle, address /* collateral */, address /* collateralOracle */) public override view returns(uint ratio, uint maxOrderVolume) {       
        Parameters storage p = parameters[oneToken];
        require(p.set, "Incremental: mintmaster is not initialized");
        (uint quote, /* uint volatility */ ) = IOracle(oneTokenOracle).read(oneToken, PRECISION);
        ratio = p.lastRatio;        
        if(quote == PRECISION) return(ratio, MAX_VOLUME);
        uint stepSize = p.stepSize;
        maxOrderVolume = MAX_VOLUME;
        if(quote < PRECISION && ratio + stepSize <= p.maxRatio) {
            ratio += stepSize;
        }
        if(quote > PRECISION && ratio - stepSize >= p.minRatio) {
            ratio -= stepSize;
        }
    }

    /**
     @notice records and returns an adjusted minting ratio for a oneToken implemtation
     @dev oneToken implementations calls this periodically, e.g. in the minting process
     */
    function updateMintingRatio(address /* collateralToken */) external override returns(uint ratio, uint maxOrderVolume) {
        return _updateMintingRatio(msg.sender, NULL_ADDRESS);
    }

    /**
     @notice records and returns an adjusted minting ratio for a oneToken implemtation
     @dev internal use only
     @param oneToken the oneToken implementation to evaluate
     */    
    function _updateMintingRatio(address oneToken, address /* collateralToken */) private returns(uint ratio, uint maxOrderVolume) {
        Parameters storage p = parameters[oneToken];
        address o = oneTokenOracles[oneToken];
        IOracle(o).update(oneToken);
        (ratio, maxOrderVolume) = getMintingRatio2(oneToken, NULL_ADDRESS);
        p.lastRatio = ratio;
        /// @notice no event is emitted to save gas
        // emit UpdateMintingRatio(msg.sender, volatility, ratio, maxOrderVolume);
    }

    /**
     * Governance functions
     */

    /**
     @notice adjusts the rate of minting ratio change
     @dev only the governance that owns the token implentation can adjust the mintMaster's parameters
     @param oneToken the implementation to work with
     @param stepSize the step size must be smaller than the difference of min and max
     */
    function setStepSize(address oneToken, uint stepSize) public onlyTokenOwner(oneToken) {
        Parameters storage p = parameters[oneToken];
        require(stepSize < p.maxRatio - p.minRatio, "Incremental: stepSize must be < max - min.");
        p.stepSize = stepSize;
        emit StepSizeSet(msg.sender, stepSize);
    }

    /**
     @notice sets the minimum minting ratio
     @dev only the governance that owns the token implentation can adjust the mintMaster's parameters
     if the new minimum is higher than current minting ratio, the current ratio will be adjusted to minRatio
     @param oneToken the implementation to work with
     @param minRatio the new lower bound for the minting ratio
     */    
    function setMinRatio(address oneToken, uint minRatio) public onlyTokenOwner(oneToken) {
        Parameters storage p = parameters[oneToken];
        require(minRatio <= p.maxRatio, "Incremental: minRatio must be <= maxRatio");
        p.minRatio = minRatio;
        if(minRatio > p.lastRatio) setRatio(oneToken, minRatio);
        emit MinRatioSet(msg.sender, minRatio);
    }

    /**
     @notice sets the maximum minting ratio
     @dev only the governance that owns the token implentation can adjust the mintMaster's parameters
     if the new maximum is lower is than current minting ratio, the current ratio will be set to maxRatio
     @param oneToken the implementation to work with
     @param maxRatio the new upper bound for the minting ratio
     */ 
    function setMaxRatio(address oneToken, uint maxRatio) public onlyTokenOwner(oneToken) {
        Parameters storage p = parameters[oneToken];
        require(maxRatio > p.minRatio, "Incremental: maxRatio must be > minRatio");
        require(maxRatio <= PRECISION, "Incremental: maxRatio must <= 100%");
        p.maxRatio = maxRatio;
        if(maxRatio < p.lastRatio) setRatio(oneToken, maxRatio);
        emit MaxRatioSet(msg.sender, maxRatio);
    }

    /**
     @notice sets the current minting ratio
     @dev only the governance that owns the token implentation can adjust the mintMaster's parameters
     @param oneToken the implementation to work with
     @param ratio must be in the min-max range
     */
    function setRatio(address oneToken, uint ratio) public onlyTokenOwner(oneToken) {
        Parameters storage p = parameters[oneToken];
        require(ratio > 0, "Incremental: ratio must be > 0");
        require(ratio <= PRECISION, "Incremental: ratio must be <= 100%");
        require(ratio >= p.minRatio, "Incremental: ratio must be >= minRatio");
        require(ratio <= p.maxRatio, "Incremental: ratio must be <= maxRatio");
        p.lastRatio = ratio;
        emit RatioSet(msg.sender, ratio);
    }
}
