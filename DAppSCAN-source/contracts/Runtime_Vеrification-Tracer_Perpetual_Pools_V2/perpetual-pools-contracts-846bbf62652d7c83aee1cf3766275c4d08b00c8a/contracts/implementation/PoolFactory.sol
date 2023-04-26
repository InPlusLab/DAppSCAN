//SPDX-License-Identifier: CC-BY-NC-ND-4.0
pragma solidity 0.8.7;

import "../interfaces/IPoolFactory.sol";
import "../interfaces/ILeveragedPool.sol";
import "../interfaces/IPoolCommitter.sol";
import "../interfaces/IERC20DecimalsWrapper.sol";
import "./LeveragedPool.sol";
import "./PoolToken.sol";
import "./PoolKeeper.sol";
import "./PoolCommitter.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

/// @title The pool factory contract
contract PoolFactory is IPoolFactory, Ownable {
    // #### Globals
    PoolToken public pairTokenBase;
    address public immutable pairTokenBaseAddress;
    LeveragedPool public poolBase;
    address public immutable poolBaseAddress;
    IPoolKeeper public poolKeeper;
    PoolCommitter public poolCommitterBase;
    address public immutable poolCommitterBaseAddress;

    // Default max leverage of 10
    uint16 public maxLeverage = 10;

    // Contract address to receive protocol fees
    address public feeReceiver;
    // Default fee; Fee value as a decimal multiplied by 10^18. For example, 0.5% is represented as 0.5 * 10^18
    uint256 public fee;

    // This is required because we must pass along *some* value for decimal
    // precision to the base pool tokens as we use the Cloneable pattern
    uint8 constant DEFAULT_NUM_DECIMALS = 18;

    uint8 constant MAX_DECIMALS = DEFAULT_NUM_DECIMALS;

    /**
     * @notice Format: Pool counter => pool address
     */
    mapping(uint256 => address) public override pools;
    uint256 public override numPools;

    /**
     * @notice Format: Pool address => validity
     */
    mapping(address => bool) public override isValidPool;

    // #### Functions
    constructor(address _feeReceiver) {
        require(_feeReceiver != address(0), "Address cannot be null");

        // Deploy base contracts
        pairTokenBase = new PoolToken(DEFAULT_NUM_DECIMALS);
        pairTokenBaseAddress = address(pairTokenBase);
        poolBase = new LeveragedPool();
        poolBaseAddress = address(poolBase);
        poolCommitterBase = new PoolCommitter(address(this));
        poolCommitterBaseAddress = address(poolCommitterBase);

        ILeveragedPool.Initialization memory baseInitialization = ILeveragedPool.Initialization(
            address(this),
            address(this),
            address(this),
            address(this),
            address(this),
            address(this),
            address(this),
            "BASE_POOL",
            15,
            30,
            0,
            1,
            address(this),
            address(0),
            address(this)
        );
        // Init bases
        poolBase.initialize(baseInitialization);

        pairTokenBase.initialize(address(this), "BASE_TOKEN", "BASE", DEFAULT_NUM_DECIMALS);
        feeReceiver = _feeReceiver;
    }

    /**
     * @notice Deploy a leveraged pool and its committer/pool tokens with given parameters
     * @param deploymentParameters Deployment parameters of the market. Some may be reconfigurable
     * @return Address of the created pool
     */
    function deployPool(PoolDeployment calldata deploymentParameters) external override returns (address) {
        address _poolKeeper = address(poolKeeper);
        require(_poolKeeper != address(0), "PoolKeeper not set");
        require(
            IOracleWrapper(deploymentParameters.oracleWrapper).deployer() == msg.sender,
            "Deployer must be oracle wrapper owner"
        );

        bytes32 uniquePoolHash = keccak256(
            abi.encode(
                deploymentParameters.leverageAmount,
                deploymentParameters.quoteToken,
                deploymentParameters.oracleWrapper
            )
        );

        PoolCommitter poolCommitter = PoolCommitter(
            Clones.cloneDeterministic(poolCommitterBaseAddress, uniquePoolHash)
        );
        poolCommitter.initialize(address(this));
        address poolCommitterAddress = address(poolCommitter);

        require(
            deploymentParameters.leverageAmount >= 1 && deploymentParameters.leverageAmount <= maxLeverage,
            "PoolKeeper: leveraged amount invalid"
        );
        require(
            IERC20DecimalsWrapper(deploymentParameters.quoteToken).decimals() <= MAX_DECIMALS,
            "Decimal precision too high"
        );

        LeveragedPool pool = LeveragedPool(Clones.cloneDeterministic(poolBaseAddress, uniquePoolHash));
        address _pool = address(pool);
        emit DeployPool(_pool, deploymentParameters.poolName);

        string memory leverage = Strings.toString(deploymentParameters.leverageAmount);

        ILeveragedPool.Initialization memory initialization = ILeveragedPool.Initialization(
            owner(), // governance is the owner of pools -- if this changes, `onlyGov` breaks
            _poolKeeper,
            deploymentParameters.oracleWrapper,
            deploymentParameters.settlementEthOracle,
            deployPairToken(_pool, leverage, deploymentParameters, "L-"),
            deployPairToken(_pool, leverage, deploymentParameters, "S-"),
            poolCommitterAddress,
            string(abi.encodePacked(leverage, "-", deploymentParameters.poolName)),
            deploymentParameters.frontRunningInterval,
            deploymentParameters.updateInterval,
            (fee * deploymentParameters.updateInterval) / (365 days),
            deploymentParameters.leverageAmount,
            feeReceiver,
            msg.sender,
            deploymentParameters.quoteToken
        );

        // approve the quote token on the pool committer to finalise linking
        // this also stores the pool address in the committer
        // finalise pool setup
        pool.initialize(initialization);
        // approve the quote token on the pool commiter to finalise linking
        // this also stores the pool address in the commiter
        IPoolCommitter(poolCommitterAddress).setQuoteAndPool(deploymentParameters.quoteToken, _pool);
        poolKeeper.newPool(_pool);
        pools[numPools] = _pool;
        numPools += 1;
        isValidPool[_pool] = true;
        return _pool;
    }

    /**
     * @notice Deploy a contract for pool tokens
     * @param leverage Amount of leverage for pool
     * @param deploymentParameters Deployment parameters for parent function
     * @param direction Long or short token, L- or S-
     * @return Address of the pool token
     */
    function deployPairToken(
        address owner,
        string memory leverage,
        PoolDeployment memory deploymentParameters,
        string memory direction
    ) internal returns (address) {
        string memory poolNameAndSymbol = string(abi.encodePacked(leverage, direction, deploymentParameters.poolName));
        uint8 settlementDecimals = IERC20DecimalsWrapper(deploymentParameters.quoteToken).decimals();
        bytes32 uniqueTokenHash = keccak256(
            abi.encode(
                deploymentParameters.leverageAmount,
                deploymentParameters.quoteToken,
                deploymentParameters.oracleWrapper,
                direction
            )
        );

        PoolToken pairToken = PoolToken(Clones.cloneDeterministic(pairTokenBaseAddress, uniqueTokenHash));
        pairToken.initialize(owner, poolNameAndSymbol, poolNameAndSymbol, settlementDecimals);
        return address(pairToken);
    }

    function setPoolKeeper(address _poolKeeper) external override onlyOwner {
        require(_poolKeeper != address(0), "address cannot be null");
        poolKeeper = IPoolKeeper(_poolKeeper);
    }

    function setMaxLeverage(uint16 newMaxLeverage) external override onlyOwner {
        require(newMaxLeverage > 0, "Maximum leverage must be non-zero");
        maxLeverage = newMaxLeverage;
    }

    function setFeeReceiver(address _feeReceiver) external override onlyOwner {
        require(_feeReceiver != address(0), "address cannot be null");
        feeReceiver = _feeReceiver;
    }

    /**
     * @notice Set the yearly fee amount. The max yearly fee is 10%
     * @dev This is a percentage in WAD; multiplied by 10^18 e.g. 5% is 0.05 * 10^18
     * @param _fee The fee amount as a percentage
     */
    function setFee(uint256 _fee) external override onlyOwner {
        require(_fee <= 0.1e18, "Fee cannot be >10%");
        fee = _fee;
    }

    function getOwner() external view override returns (address) {
        return owner();
    }

    modifier onlyGov() {
        require(msg.sender == owner(), "msg.sender not governance");
        _;
    }
}
