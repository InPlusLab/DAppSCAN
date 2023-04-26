// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "../interfaces/ITokenExchange.sol";
import "../connectors/balancer/interfaces/IVault.sol";
import "../connectors/balancer/interfaces/IAsset.sol";

contract Mta2UsdcTokenExchange is ITokenExchange {

    IVault public balancerVault;
    IERC20 public usdcToken;
    IERC20 public wmaticToken;
    IERC20 public mtaToken;
    bytes32 public balancerPoolId1;
    bytes32 public balancerPoolId2;

    constructor(
        address _balancerVault,
        address _usdcToken,
        address _wmaticToken,
        address _mtaToken,
        bytes32 _balancerPoolId1,
        bytes32 _balancerPoolId2
    ) {
        require(_balancerVault != address(0), "Zero address not allowed");
        require(_usdcToken != address(0), "Zero address not allowed");
        require(_wmaticToken != address(0), "Zero address not allowed");
        require(_mtaToken != address(0), "Zero address not allowed");
        require(_balancerPoolId1 != "", "Empty pool id not allowed");
        require(_balancerPoolId2 != "", "Empty pool id not allowed");

        balancerVault = IVault(_balancerVault);
        usdcToken = IERC20(_usdcToken);
        wmaticToken = IERC20(_wmaticToken);
        mtaToken = IERC20(_mtaToken);
        balancerPoolId1 = _balancerPoolId1;
        balancerPoolId2 = _balancerPoolId2;
    }

    function exchange(
        address spender,
        IERC20 from,
        address receiver,
        IERC20 to,
        uint256 amount
    ) external override {
        require(
            (from == usdcToken && to == mtaToken) || (from == mtaToken && to == usdcToken),
            "Mta2UsdcTokenExchange: Some token not compatible"
        );

        if (amount == 0) {
            from.transfer(spender, from.balanceOf(address(this)));
            return;
        }

        if (from == usdcToken && to == mtaToken) {
            revert("Mta2UsdcTokenExchange: Allowed only exchange MTA to USDC");
        } else {
            //TODO: denominator usage
            uint256 denominator = 10**(18 - IERC20Metadata(address(mtaToken)).decimals());
            amount = amount / denominator;

            require(
                mtaToken.balanceOf(address(this)) >= amount,
                "Mta2UsdcTokenExchange: Not enough mtaToken"
            );

            // check after denormilization
            if (amount == 0) {
                from.transfer(spender, from.balanceOf(address(this)));
                return;
            }

            mtaToken.approve(address(balancerVault), amount);

            IVault.BatchSwapStep[] memory swaps = new IVault.BatchSwapStep[](2);
            IVault.BatchSwapStep memory batchSwap1;
            batchSwap1.poolId = balancerPoolId1;
            batchSwap1.assetInIndex = 0;
            batchSwap1.assetOutIndex = 1;
            batchSwap1.amount = amount;
            swaps[0] = batchSwap1;
            IVault.BatchSwapStep memory batchSwap2;
            batchSwap2.poolId = balancerPoolId2;
            batchSwap2.assetInIndex = 1;
            batchSwap2.assetOutIndex = 2;
            batchSwap2.amount = 0;
            swaps[1] = batchSwap2;

            IAsset[] memory assets = new IAsset[](3);
            assets[0] = IAsset(address(mtaToken));
            assets[1] = IAsset(address(wmaticToken));
            assets[2] = IAsset(address(usdcToken));

            IVault.FundManagement memory fundManagement;
            fundManagement.sender = address(this);
            fundManagement.fromInternalBalance = false;
            fundManagement.recipient = payable(receiver);
            fundManagement.toInternalBalance = false;

            int256[] memory limits = new int256[](3);
            limits[0] = (10 ** 27);
            limits[1] = (10 ** 27);
            limits[2] = (10 ** 27);

            balancerVault.batchSwap(IVault.SwapKind.GIVEN_IN, swaps, assets, fundManagement, limits, block.timestamp + 600);
        }
    }
}
