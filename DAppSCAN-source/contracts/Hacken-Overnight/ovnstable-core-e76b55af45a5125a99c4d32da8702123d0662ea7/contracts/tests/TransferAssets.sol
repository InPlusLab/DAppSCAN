pragma solidity ^0.8.6;

import "../Vault.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "../registries/Portfolio.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "hardhat/console.sol";

contract TransferAssets is AccessControl {

    Vault public oldVault;
    Vault public newVault;
    Portfolio public portfolio;


    modifier onlyAdmin() {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Restricted to admins");
        _;
    }

    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }


    function setVaults(address _oldVault, address _newVault, address _portfolio) external onlyAdmin {
        oldVault = Vault(_oldVault);
        newVault = Vault(_newVault);
        portfolio = Portfolio(_portfolio);
    }


    function move() external onlyAdmin {
        Portfolio.AssetInfo[] memory assetInfos = portfolio.getAllAssetInfos();
        console.log("AssetInfo %s", assetInfos.length);
        uint256 count = assetInfos.length;
        for (uint8 i = 0; i < count; i++) {
            Portfolio.AssetInfo memory assetInfo = assetInfos[i];

            IERC20 asset = IERC20(assetInfo.asset);

            uint256 balance = asset.balanceOf(address(oldVault));
            console.log("Transfer %s , %s, balance %s", address(oldVault), address(newVault), balance);

            if(balance > 0){
                oldVault.transfer(asset, address(newVault), balance);
            }
        }
    }
}
