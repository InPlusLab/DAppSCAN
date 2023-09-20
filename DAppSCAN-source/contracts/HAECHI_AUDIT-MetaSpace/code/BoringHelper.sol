// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.0;

pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IGravityCenter.sol";
import "./interfaces/IPair.sol";
import "./interfaces/IFactory.sol";
import "./libraries/BoringMath.sol";
import "./libraries/BoringERC20.sol";
import "./libraries/BoringPair.sol";
import "./interfaces/IOracle.sol";


contract BoringHelper is Ownable {
    using BoringMath for uint256;
    using BoringERC20 for IERC20;
    using BoringERC20 for IPair;
    using BoringPair for IPair;

    IGravityCenter public gravity; // IMasterChef(0xc2EdaD668740f1aA35E4D8f227fB8E17dcA888Cd);
    IERC20 public mspace; // ISushiToken(0x6B3595068778DD592e39A122f4f5a5cF09C90fE2);
    IERC20 public WMETA; // 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    IERC20 public WETH; // 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    IFactory public factory; // IFactory(0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac);
    IERC20 public space; // 0x8798249c2E607446EfB7Ad49eC89dD1865Ff4272;

    constructor(
        IGravityCenter gravity_,
        IERC20 mspace_,
        IERC20 WMETA_,
        IERC20 WETH_,
        IFactory factory_,
        IERC20 space_
    ) {
        gravity = gravity_;
        mspace = mspace_;
        WMETA = WMETA_;
        WETH = WETH_;
        factory = factory_;
        space = space_;
    }

    function setContracts(
        IGravityCenter gravity_,
        IERC20 mspace_,
        IERC20 WMETA_,
        IERC20 WETH_,
        IFactory factory_,
        IERC20 space_
    ) public onlyOwner {
        gravity = gravity_;
        mspace = mspace_;
        WMETA = WMETA_;
        WETH = WETH_;
        factory = factory_;
        space = space_;
    }
//SWC-135-Code With No Effects: L77
    function getMETARate(IERC20 token) public view returns (uint256) {
        if (token == WMETA) {
            return 1e18;
        }
        IPair pair;
        if (factory != IFactory(address(0))) {
            pair = IPair(factory.getPair(token, WMETA));
        }
        if (address(pair) == address(0)) {
            return 0;
        }

        uint112 reserve0;
        uint112 reserve1;
        IERC20 token0;

        if (address(pair) != address(0)) {
            (uint112 reserve0MSpace, uint112 reserve1MSpace, ) = pair.getReserves();
            reserve0 += reserve0MSpace;
            reserve1 += reserve1MSpace;
            if (token0 == IERC20(address(0))) {
                token0 = pair.token0();
            }
        }

        if (token0 == WMETA) {
            return (uint256(reserve1) * 1e18) / reserve0;
        } else {
            return (uint256(reserve0) * 1e18) / reserve1;
        }
    }

    struct Factory {
        IFactory factory;
        uint256 allPairsLength;
    }

    struct UIInfo {
        uint256 metaBalance;
        uint256 mspaceBalance;
        uint256 spaceBalance;
        uint256 xstarBalance;
        uint256 xstarSupply;
        uint256 spaceAllowance;
        Factory[] factories;
        uint256 metaRate;
        uint256 mspaceRate;
        uint256 ethRate;
        uint256 pendingMSpace;
        uint256 blockTimeStamp;
    }

    function getUIInfo(
        address who,
        IFactory[] calldata factoryAddresses,
        IERC20 currency
    ) public view returns (UIInfo memory) {
        UIInfo memory info;
        info.metaBalance = who.balance;

        info.factories = new Factory[](factoryAddresses.length);
        for (uint256 i = 0; i < factoryAddresses.length; i++) {
            IFactory factory_ = factoryAddresses[i];
            info.factories[i].factory = factory_;
            info.factories[i].allPairsLength = factory_.allPairsLength();
        }

        if (currency != IERC20(address(0))) {
            info.metaRate = getMETARate(currency);
        }

        if (WETH != IERC20(address(0))) {
            info.ethRate = getMETARate(WETH);
        }

        if (mspace != IERC20(address(0))) {
            info.mspaceRate = getMETARate(mspace);
            info.mspaceBalance = mspace.balanceOf(who);
            info.spaceBalance = mspace.balanceOf(address(space));
            info.spaceAllowance = mspace.allowance(who, address(space));
        }

        if (space != IERC20(address(0))) {
            info.xstarBalance = space.balanceOf(who);
            info.xstarSupply = space.totalSupply();
        }

        if (gravity != IGravityCenter(address(0))) {
            uint256 poolLength = gravity.poolLength();
            uint256 pendingMSpace;
            for (uint256 i = 0; i < poolLength; i++) {
                pendingMSpace += gravity.pendingMSpace(i, who);
            }
            info.pendingMSpace = pendingMSpace;
        }
        info.blockTimeStamp = block.timestamp;

        return info;
    }

    struct Balance {
        IERC20 token;
        uint256 balance;
    }

    struct BalanceFull {
        IERC20 token;
        uint256 totalSupply;
        uint256 balance;
        uint256 nonce;
        uint256 rate;
    }

    struct TokenInfo {
        IERC20 token;
        uint256 decimals;
        string name;
        string symbol;
        bytes32 DOMAIN_SEPARATOR;
    }

    function getTokenInfo(address[] calldata addresses) public view returns (TokenInfo[] memory) {
        TokenInfo[] memory infos = new TokenInfo[](addresses.length);

        for (uint256 i = 0; i < addresses.length; i++) {
            IERC20 token = IERC20(addresses[i]);
            infos[i].token = token;

            infos[i].name = token.name();
            infos[i].symbol = token.symbol();
            infos[i].decimals = token.decimals();
            infos[i].DOMAIN_SEPARATOR = token.DOMAIN_SEPARATOR();
        }

        return infos;
    }

    function findBalances(address who, address[] calldata addresses) public view returns (Balance[] memory) {
        Balance[] memory balances = new Balance[](addresses.length);

        uint256 len = addresses.length;
        for (uint256 i = 0; i < len; i++) {
            IERC20 token = IERC20(addresses[i]);
            balances[i].token = token;
            balances[i].balance = token.balanceOf(who);
        }

        return balances;
    }

    function getBalances(address who, IERC20[] calldata addresses) public view returns (BalanceFull[] memory) {
        BalanceFull[] memory balances = new BalanceFull[](addresses.length);

        for (uint256 i = 0; i < addresses.length; i++) {
            IERC20 token = addresses[i];
            balances[i].totalSupply = token.totalSupply();
            balances[i].token = token;
            balances[i].balance = token.balanceOf(who);
            balances[i].nonce = token.nonces(who);
            balances[i].rate = getMETARate(token);
        }

        return balances;
    }

    struct PairBase {
        IPair token;
        IERC20 token0;
        IERC20 token1;
        uint256 totalSupply;
    }

    function getPairs(
        IFactory factory_,
        uint256 fromID,
        uint256 toID
    ) public view returns (PairBase[] memory) {
        PairBase[] memory pairs = new PairBase[](toID - fromID);

        for (uint256 id = fromID; id < toID; id++) {
            IPair token = factory_.allPairs(id);
            uint256 i = id - fromID;
            pairs[i].token = token;
            pairs[i].token0 = token.token0();
            pairs[i].token1 = token.token1();
            pairs[i].totalSupply = token.totalSupply();
        }
        return pairs;
    }

    struct PairPoll {
        IPair token;
        uint256 reserve0;
        uint256 reserve1;
        uint256 totalSupply;
        uint256 balance;
    }

    function pollPairs(address who, IPair[] calldata addresses) public view returns (PairPoll[] memory) {
        PairPoll[] memory pairs = new PairPoll[](addresses.length);
        for (uint256 i = 0; i < addresses.length; i++) {
            IPair token = addresses[i];
            pairs[i].token = token;
            (uint256 reserve0, uint256 reserve1, ) = token.getReserves();
            pairs[i].reserve0 = reserve0;
            pairs[i].reserve1 = reserve1;
            pairs[i].balance = token.balanceOf(who);
            pairs[i].totalSupply = token.totalSupply();
        }
        return pairs;
    }

    struct PoolsInfo {
        uint256 totalAllocPoint;
        uint256 poolLength;
    }

    struct PoolInfo {
        uint256 pid;
        IPair lpToken;
        uint256 allocPoint;
        bool isPair;
        IFactory factory;
        IERC20 token0;
        IERC20 token1;
        string name;
        string symbol;
        uint8 decimals;
    }

    function getPools(uint256[] calldata pids) public view returns (PoolsInfo memory, PoolInfo[] memory) {
        PoolsInfo memory info;
        info.totalAllocPoint = gravity.totalAllocPoint();
        uint256 poolLength = gravity.poolLength();
        info.poolLength = poolLength;

        PoolInfo[] memory pools = new PoolInfo[](pids.length);

        for (uint256 i = 0; i < pids.length; i++) {
            pools[i].pid = pids[i];
            (address lpToken, uint256 allocPoint, , ) = gravity.poolInfo(pids[i]);
            IPair uniV2 = IPair(lpToken);
            pools[i].lpToken = uniV2;
            pools[i].allocPoint = allocPoint;

            pools[i].name = uniV2.name();
            pools[i].symbol = uniV2.symbol();
            pools[i].decimals = uniV2.decimals();

            pools[i].factory = uniV2.factory();
            if (pools[i].factory != IFactory(address(0))) {
                pools[i].isPair = true;
                pools[i].token0 = uniV2.token0();
                pools[i].token1 = uniV2.token1();
            }
        }
        return (info, pools);
    }

    struct PoolFound {
        uint256 pid;
        uint256 balance;
    }

    function findPools(address who, uint256[] calldata pids) public view returns (PoolFound[] memory) {
        PoolFound[] memory pools = new PoolFound[](pids.length);

        for (uint256 i = 0; i < pids.length; i++) {
            pools[i].pid = pids[i];
            (pools[i].balance, ) = gravity.userInfo(pids[i], who);
        }

        return pools;
    }

    struct UserPoolInfo {
        uint256 pid;
        uint256 balance; // Balance of pool tokens
        uint256 totalSupply; // Token staked lp tokens
        uint256 lpBalance; // Balance of lp tokens not staked
        uint256 lpTotalSupply; // TotalSupply of lp tokens
        uint256 lpAllowance; // LP tokens approved for masterchef
        uint256 reserve0;
        uint256 reserve1;
        uint256 rewardDebt;
        uint256 pending; // Pending SUSHI
    }

    function pollPools(address who, uint256[] calldata pids) public view returns (UserPoolInfo[] memory) {
        UserPoolInfo[] memory pools = new UserPoolInfo[](pids.length);

        for (uint256 i = 0; i < pids.length; i++) {
            (uint256 amount, ) = gravity.userInfo(pids[i], who);
            pools[i].balance = amount;
            pools[i].pending = gravity.pendingMSpace(pids[i], who);

            (address lpToken, , , ) = gravity.poolInfo(pids[i]);
            pools[i].pid = pids[i];
            IPair pair = IPair(lpToken);
            IFactory factory_ = pair.factory();
            if (factory_ != IFactory(address(0))) {
                pools[i].totalSupply = pair.balanceOf(address(gravity));
                pools[i].lpAllowance = pair.allowance(who, address(gravity));
                pools[i].lpBalance = pair.balanceOf(who);
                pools[i].lpTotalSupply = pair.totalSupply();

                (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();
                pools[i].reserve0 = reserve0;
                pools[i].reserve1 = reserve1;
            }
        }
        return pools;
    }
}