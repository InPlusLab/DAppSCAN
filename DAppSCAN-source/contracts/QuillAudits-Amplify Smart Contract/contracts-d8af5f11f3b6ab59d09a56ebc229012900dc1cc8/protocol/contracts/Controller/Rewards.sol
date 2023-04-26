// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../utils/ExponentialDouble.sol";

abstract contract Rewards is ExponentialDouble {
    struct Reward {
        uint index;
        uint accrued;
    }

    struct PoolState {
        bool isCreated;
        uint supplyIndex;
        uint borrowIndex;
        uint supplyBlockNumber;
        uint borrowBlockNumber;
    }

    mapping(address => mapping(address => Reward)) public borrowerState;
    mapping(address => mapping(address => Reward)) public supplierState;
    mapping(address => PoolState) public rewardsState;
    mapping(address => uint) public amptPoolSpeeds;
    address[] public rewardPools;

    function getTotalBorrowReward(address account) external view returns (uint256) {
        uint256 totalAmount;
        for(uint256 i=0; i< rewardPools.length; i++) {
            totalAmount += this.getBorrowReward(account, rewardPools[i]);
        }
        return totalAmount;
    }

    function getBorrowReward(address account, address pool) external view returns (uint256) {
        uint256 poolIndex = getNewBorrowIndex(pool);
        return getBorrowerAccruedAmount(pool, account, poolIndex);
    }

    function getTotalSupplyReward(address account) external view returns (uint256) {
        uint256 totalAmount;
        for(uint256 i=0; i< rewardPools.length; i++) {
            totalAmount += this.getSupplyReward(account, rewardPools[i]);
        }
        return totalAmount;
    }

    function getSupplyReward(address account, address pool) external view returns (uint256) {
        uint256 poolIndex = getNewSupplyIndex(pool);
        return getSupplierAccruedAmount(pool, account, poolIndex);
    }

    function claimAMPT(address holder) public {
        require(holder == msg.sender, "Only holder can claim reward");
        claimAMPT(holder, rewardPools);
    }

    function claimAMPT(address holder, address[] memory poolsList) public {
        address[] memory holders = new address[](1);
        holders[0] = holder;
        claimAMPT(holders, poolsList, true, true);
    }

    function claimAMPT(address[] memory holders, address[] memory poolsList, bool borrowers, bool suppliers) public {
        for (uint8 i = 0; i < poolsList.length; i++) {
            address pool = poolsList[i];
            if (borrowers == true) {
                updateBorrowIndexInternal(pool);
                for (uint8 j = 0; j < holders.length; j++) {
                    distributeBorrowerTokens(pool, holders[j]);
                    borrowerState[holders[j]][pool].accrued = grantRewardInternal(holders[j], borrowerState[holders[j]][pool].accrued);
                }
            }
            if (suppliers == true) {
                updateSupplyIndexInternal(pool);
                for (uint8 j = 0; j < holders.length; j++) {
                    distributeSupplierTokens(pool, holders[j]);
                    supplierState[holders[j]][pool].accrued = grantRewardInternal(holders[j], supplierState[holders[j]][pool].accrued);
                }
            }
        }
    }

    function updateBorrowIndexInternal(address pool) internal {
        rewardsState[pool].borrowIndex = getNewBorrowIndex(pool);
        rewardsState[pool].borrowBlockNumber = getBlockNumber();
    }

    struct BorrowIndexLocalVars {
        uint256 speed;
        uint256 totalPrincipal;
        uint256 blockNumber;
        uint256 deltaBlocks;
        uint256 tokensAccrued;
        Double ratio;
        Double index;
    }
    function getNewBorrowIndex(address pool) internal view returns (uint256) {
        BorrowIndexLocalVars memory vars;
        PoolState storage poolState = rewardsState[pool];

        vars.speed = amptPoolSpeeds[pool];
        (, vars.totalPrincipal) = getPoolInfo(pool);
        vars.blockNumber = getBlockNumber();
        vars.deltaBlocks = sub_(vars.blockNumber, poolState.borrowBlockNumber);
        if (vars.deltaBlocks > 0 && vars.speed > 0) {
            vars.tokensAccrued = mul_(vars.deltaBlocks, vars.speed / 2); 
            vars.ratio = vars.totalPrincipal > 0 ? fraction(vars.tokensAccrued, vars.totalPrincipal) : Double({mantissa: 0});
            vars.index = add_(Double({mantissa: poolState.borrowIndex }), vars.ratio);
            return vars.index.mantissa;
        } else {
            return poolState.borrowIndex;
        }

    }

    function updateSupplyIndexInternal(address pool) internal {
        rewardsState[pool].supplyIndex = getNewSupplyIndex(pool);
        rewardsState[pool].supplyBlockNumber = getBlockNumber();
    }

    struct SupplyIndexLocalVars {
        uint256 speed;
        uint256 totalSupply;
        uint256 blockNumber;
        uint256 deltaBlocks;
        uint256 tokensAccrued;
        Double ratio;
        Double index;
    }  
    function getNewSupplyIndex(address pool) internal view returns (uint256) {
        SupplyIndexLocalVars memory vars;
        PoolState storage poolState = rewardsState[pool];

        vars.speed = amptPoolSpeeds[pool];
        (vars.totalSupply, ) = getPoolInfo(pool);
        vars.blockNumber = getBlockNumber();
        vars.deltaBlocks = sub_(vars.blockNumber, poolState.supplyBlockNumber);
        if (vars.deltaBlocks > 0 && vars.speed > 0) {
            vars.tokensAccrued = mul_(vars.deltaBlocks, vars.speed / 2); 
            vars.ratio = vars.totalSupply > 0 ? fraction(vars.tokensAccrued, vars.totalSupply) : Double({mantissa: 0});
            vars.index = add_(Double({mantissa: poolState.supplyIndex }), vars.ratio);
            
            return vars.index.mantissa;
        }

        return poolState.supplyIndex;
    }

    function distributeBorrowerTokens(address pool, address holder) internal {
        PoolState storage borrowState = rewardsState[pool];

        borrowerState[holder][pool] = Reward({
            index: borrowState.borrowIndex,
            accrued: getBorrowerAccruedAmount(pool, holder, borrowState.borrowIndex)
        });
    }

    struct BorrowerAccruedLocalVars {
        uint256 borrowerAmount;
        uint256 borrowerDelta;
        uint256 borrowerAccrued;
        Double deltaIndex;
    }
    function getBorrowerAccruedAmount(address pool, address holder, uint poolIndex) internal view returns (uint256) {
        BorrowerAccruedLocalVars memory vars;
        Reward storage poolState = borrowerState[holder][pool];

        vars.deltaIndex = sub_(Double({mantissa: poolIndex }), Double({mantissa: poolState.index}));
        vars.borrowerAmount = getBorrowerTotalPrincipal(pool, holder);
        vars.borrowerDelta = mul_(vars.borrowerAmount, vars.deltaIndex);
        vars.borrowerAccrued = add_(poolState.accrued, vars.borrowerDelta);

        return vars.borrowerAccrued;
    }

    function distributeSupplierTokens(address pool, address holder) internal {
        PoolState storage supplyState = rewardsState[pool];

        supplierState[holder][pool] = Reward({
            index: supplyState.supplyIndex,
            accrued: getSupplierAccruedAmount(pool, holder, supplyState.supplyIndex)
        });
    }

    struct SupplierAccruedLocalVars {
        uint256 supplierBalance;
        uint256 supplierDelta;
        uint256 supplierAccrued;
        Double deltaIndex;
    }
    function getSupplierAccruedAmount(address pool, address holder, uint poolIndex) internal view returns (uint) {
        SupplierAccruedLocalVars memory vars;
        Reward storage state = supplierState[holder][pool];

        vars.deltaIndex = sub_(Double({mantissa: poolIndex }), Double({mantissa: state.index}));
        vars.supplierBalance = getSupplierBalance(pool, holder);
        vars.supplierDelta = mul_(vars.supplierBalance, vars.deltaIndex);
        vars.supplierAccrued = add_(state.accrued, vars.supplierDelta);
        return vars.supplierAccrued;
    }

    function getBorrowerTotalPrincipal(address pool, address holder) internal virtual view returns (uint256);
    
    function getSupplierBalance(address pool, address holder) internal virtual view returns (uint256);

    function getPoolInfo(address pool) internal virtual view returns (uint256, uint256);

    function grantRewardInternal(address account, uint256 amount) internal virtual returns (uint256);

    function getBlockNumber() public virtual view returns(uint256);
}