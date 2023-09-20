// SPDX-License-Identifier: NO LICENSE
pragma solidity 0.7.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol"; // for WETH
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IWETH.sol";
import "./SHEESHA.sol";
import "./ISHEESHAGlobals.sol";

interface ISHEESHAVaultLP {
    function depositFor(
        address,
        uint256,
        uint256
    ) external;
}

contract LGE is SHEESHA {
    using SafeMath for uint256;
    address public SHEESHAxWETHPair;
    IUniswapV2Router02 public uniswapRouterV2;
    IUniswapV2Factory public uniswapFactory;
    uint256 public totalLPTokensMinted;
    uint256 public totalETHContributed;
    uint256 public LPperETHUnit;
    bool public LPGenerationCompleted;
    uint256 public contractStartTimestamp;
    uint256 public constant lgeSupply = 15000e18; // 15k
    //user count
    uint256 public userCount;
    ISHEESHAGlobals public sheeshaGlobals;
    uint256 public stakeCount;
//SWC-131-Presence of unused variables:L34
    mapping(address => uint256) public ethContributed;
    mapping(address => bool) public claimed;
    mapping(uint256 => address) public userList;

    event LiquidityAddition(address indexed dst, uint256 value);
    event LPTokenClaimed(address dst, uint256 value);

    constructor(
        address router,
        address factory,
        ISHEESHAGlobals _sheeshaGlobals,
        address _devAddress,
        address _marketingAddress,
        address _teamAddress,
        address _reserveAddress
    ) SHEESHA(_devAddress, _marketingAddress, _teamAddress, _reserveAddress) {
        uniswapRouterV2 = IUniswapV2Router02(
            router != address(0)
                ? router
                : 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D
        ); // For testing
        uniswapFactory = IUniswapV2Factory(
            factory != address(0)
                ? factory
                : 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f
        ); // For testing
        createUniswapPairMainnet();
        contractStartTimestamp = block.timestamp;
        sheeshaGlobals = _sheeshaGlobals;
    }

    function getSecondsLeftInLiquidityGenerationEvent()
        public
        view
        returns (uint256)
    {
        require(liquidityGenerationOngoing(), "Event over");
        return contractStartTimestamp.add(14 days).sub(block.timestamp);
    }

    function liquidityGenerationOngoing() public view returns (bool) {
        //lge only for 2 weeks
        return contractStartTimestamp.add(14 days) > block.timestamp;
    }

    function createUniswapPairMainnet() public returns (address) {
        require(SHEESHAxWETHPair == address(0), "Token: pool already created");
        SHEESHAxWETHPair = uniswapFactory.createPair(
            address(uniswapRouterV2.WETH()),
            address(this)
        );
        return SHEESHAxWETHPair;
    }
//SWC-129-Typographical Error:L91、126、134
    //anyone/admin will call this function after 2 weeks to mint LGE
    // Sends all avaibile balances and mints LP tokens
    // Possible ways this could break addressed
    // 1) Multiple calls and resetting amounts - addressed with boolean
    // 2) Failed WETH wrapping/unwrapping addressed with checks
    // 3) Failure to create LP tokens, addressed with checks
    // 4) Unacceptable division errors . Addressed with multiplications by 1e18
    // 5) Pair not set - impossible since its set in constructor
    function addLiquidityToUniswapSHEESHAxWETHPair() public {
        require(
            liquidityGenerationOngoing() == false,
            "Liquidity generation ongoing"
        );
        require(
            LPGenerationCompleted == false,
            "Liquidity generation already finished"
        );
        totalETHContributed = address(this).balance;
        IUniswapV2Pair pair = IUniswapV2Pair(SHEESHAxWETHPair);
        //Wrap eth
        address WETH = uniswapRouterV2.WETH();
        IWETH(WETH).deposit{value: totalETHContributed}();
        require(address(this).balance == 0, "Transfer Failed");
        IWETH(WETH).transfer(address(pair), totalETHContributed);
        transfer(address(pair), lgeSupply); // 15% in LGE
        pair.mint(address(this));
        totalLPTokensMinted = pair.balanceOf(address(this));
        require(totalLPTokensMinted != 0, "LP creation failed");
        LPperETHUnit = totalLPTokensMinted.mul(1e18).div(totalETHContributed); // 1e18x for  change
        require(LPperETHUnit != 0, "LP creation failed");
        LPGenerationCompleted = true;
    }

    //people will send ETH to this function for LGE
    // Possible ways this could break addressed
    // 1) Adding liquidity after generaion is over - added require
    // 2) Overflow from uint - impossible there isnt that much ETH aviable
    // 3) Depositing 0 - not an issue it will just add 0 to tally
    function addLiquidity() public payable {
        require(
            liquidityGenerationOngoing() == true,
            "Liquidity Generation Event over"
        );
        ethContributed[msg.sender] += msg.value; // Overflow protection from safemath is not neded here
        totalETHContributed = totalETHContributed.add(msg.value); // for front end display during LGE. This resets with definietly correct balance while calling pair.
        userList[userCount] = msg.sender;
        userCount++;
        emit LiquidityAddition(msg.sender, msg.value);
    }

    // Possible ways this could break addressed
    // 1) Accessing before event is over and resetting eth contributed -- added require
    // 2) No uniswap pair - impossible at this moment because of the LPGenerationCompleted bool
    // 3) LP per unit is 0 - impossible checked at generation function
    function _claimLPTokens() internal returns (uint256 amountLPToTransfer) {
        amountLPToTransfer = ethContributed[msg.sender].mul(LPperETHUnit).div(
            1e18
        );
        ethContributed[msg.sender] = 0;
        claimed[msg.sender] = true;
    }

    //pool id must be pool id of SHEESHAXWETH LP vault
    function claimAndStakeLP(uint256 _pid) public {
        require(
            LPGenerationCompleted == true,
            "LGE : Liquidity generation not finished yet"
        );
        require(ethContributed[msg.sender] > 0, "Nothing to claim, move along");
        require(claimed[msg.sender] == false, "LGE : Already claimed");
        address vault = sheeshaGlobals.SHEESHAVaultLPAddress();
        IUniswapV2Pair(SHEESHAxWETHPair).approve(vault, uint256(-1));
        ISHEESHAVaultLP(vault).depositFor(msg.sender, _pid, _claimLPTokens());
    }

    function getLPTokens(address _who)
        public
        view
        returns (uint256 amountLPToTransfer)
    {
        return ethContributed[_who].mul(LPperETHUnit).div(1e18);
    }

    // Emergency drain in case of a bug
    // Adds all funds to owner to refund people
    // Designed to be as simple as possible
    function emergencyDrain24hAfterLiquidityGenerationEventIsDone()
        public
        payable
        onlyOwner
    {
        require(
            contractStartTimestamp.add(15 days) < block.timestamp,
            "Liquidity generation grace period still ongoing"
        ); // About 24h after liquidity generation happens
        msg.sender.transfer(address(this).balance);
        _transfer(address(this), msg.sender, balanceOf(address(this)));
    }
}
