//SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "../Permissions/IRoleManager.sol";
import "../Parameters/IParameterManager.sol";
import "../Maker/IMakerRegistrar.sol";
import "../Token/IStandard1155.sol";
import "../Reactions/IReactionVault.sol";
import "../CuratorVault/ICuratorVault.sol";

interface IAddressManager {
    /// @dev Getter for the role manager address
    function roleManager() external returns (IRoleManager);

    /// @dev Setter for the role manager address
    function setRoleManager(IRoleManager _roleManager) external;

    /// @dev Getter for the role manager address
    function parameterManager() external returns (IParameterManager);

    /// @dev Setter for the role manager address
    function setParameterManager(IParameterManager _parameterManager) external;

    /// @dev Getter for the maker registrar address
    function makerRegistrar() external returns (IMakerRegistrar);

    /// @dev Setter for the maker registrar address
    function setMakerRegistrar(IMakerRegistrar _makerRegistrar) external;

    /// @dev Getter for the reaction NFT contract address
    function reactionNftContract() external returns (IStandard1155);

    /// @dev Setter for the reaction NFT contract address
    function setReactionNftContract(IStandard1155 _reactionNftContract)
        external;

    /// @dev Getter for the default Curator Vault contract address
    function defaultCuratorVault() external returns (ICuratorVault);

    /// @dev Setter for the default Curator Vault contract address
    function setDefaultCuratorVault(ICuratorVault _defaultCuratorVault)
        external;

    /// @dev Getter for the L2 bridge registrar
    function childRegistrar() external returns (address);

    /// @dev Setter for the L2 bridge registrar
    function setChildRegistrar(address _childRegistrar) external;
}
