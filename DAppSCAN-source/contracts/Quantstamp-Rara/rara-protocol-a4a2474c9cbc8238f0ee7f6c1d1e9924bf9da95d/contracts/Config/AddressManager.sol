//SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./AddressManagerStorage.sol";

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract AddressManager is Initializable, AddressManagerStorageV1 {
    /// @dev Verifies with the role manager that the calling address has ADMIN role
    modifier onlyAdmin() {
        require(roleManager.isAddressManagerAdmin(msg.sender), "Not Admin");
        _;
    }

    /// @dev initializer to call after deployment, can only be called once
    function initialize(IRoleManager _roleManager) public initializer {
        require(address(_roleManager) != address(0x0), ZERO_INPUT);
        roleManager = _roleManager;
    }

    /// @dev Setter for the role manager address
    function setRoleManager(IRoleManager _roleManager) external onlyAdmin {
        // Sanity check
        require(address(_roleManager) != address(0x0), ZERO_INPUT);

        // If the role manager address gets corrupted then this contract is DOA
        // since no future updates can be performed via permission checks.
        // Ensure the target address is valid and configured by requiring the current admin
        // making this call is an admin on the new contract
        require(_roleManager.isAdmin(msg.sender), "RM invalid");

        roleManager = _roleManager;
    }

    /// @dev Setter for the role manager address
    function setParameterManager(IParameterManager _parameterManager)
        external
        onlyAdmin
    {
        require(address(_parameterManager) != address(0x0), ZERO_INPUT);
        parameterManager = _parameterManager;
    }

    /// @dev Setter for the maker registrar address
    function setMakerRegistrar(IMakerRegistrar _makerRegistrar)
        external
        onlyAdmin
    {
        require(address(_makerRegistrar) != address(0x0), ZERO_INPUT);
        makerRegistrar = _makerRegistrar;
    }

    /// @dev Setter for the maker registrar address
    function setReactionNftContract(IStandard1155 _reactionNftContract)
        external
        onlyAdmin
    {
        require(address(_reactionNftContract) != address(0x0), ZERO_INPUT);
        reactionNftContract = _reactionNftContract;
    }

    /// @dev Setter for the default curator vault address
    function setDefaultCuratorVault(ICuratorVault _defaultCuratorVault)
        external
        onlyAdmin
    {
        require(address(_defaultCuratorVault) != address(0x0), ZERO_INPUT);
        defaultCuratorVault = _defaultCuratorVault;
    }

    /// @dev Setter for the L2 bridge registrar
    function setChildRegistrar(address _childRegistrar) external onlyAdmin {
        require(address(_childRegistrar) != address(0x0), ZERO_INPUT);
        childRegistrar = _childRegistrar;
    }
}
