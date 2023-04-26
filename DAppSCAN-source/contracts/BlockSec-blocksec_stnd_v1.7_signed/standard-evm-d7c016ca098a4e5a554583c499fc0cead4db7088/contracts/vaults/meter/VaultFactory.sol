// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "./Vault.sol";
import "./interfaces/IVaultFactory.sol";

contract VaultFactory is AccessControl, IVaultFactory {

    // Vaults
    address[] public allVaults;
    /// Address of uniswapv2 factory
    address public override v2Factory;
    /// Address of cdp nft registry
    address public override v1;
    /// Address of Wrapped Ether
    address public override WETH;
    /// Address of manager
    address public override manager;

    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }

    /// Vault cannot issue stablecoin, it just manages the position
    function createVault(address collateral_, address debt_, uint256 amount_, address recipient) external override returns (address vault, uint256 id) {
        uint256 gIndex = allVaultsLength();
        IV1(v1).mint(recipient, gIndex);
        bytes memory bytecode = type(Vault).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(gIndex));
        assembly {
            vault := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        Vault(vault).initialize(manager, gIndex, collateral_, debt_, v1, amount_, v2Factory, WETH);
        allVaults.push(vault);
        return (vault, gIndex);
    }

    function initialize(address v1_, address v2Factory_, address weth_, address manager_) public {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "IA"); // Invalid Access
        v1 = v1_;
        v2Factory = v2Factory_;
        WETH = weth_;
        manager = manager_;
    }

    function getVault(uint vaultId_) external view override returns (address) {
        return allVaults[vaultId_];
    }


    function vaultCodeHash() external pure override returns (bytes32 vaultCode) {
        return keccak256(type(Vault).creationCode);
    }

    function allVaultsLength() public view returns (uint) {
        return allVaults.length;
    }
}