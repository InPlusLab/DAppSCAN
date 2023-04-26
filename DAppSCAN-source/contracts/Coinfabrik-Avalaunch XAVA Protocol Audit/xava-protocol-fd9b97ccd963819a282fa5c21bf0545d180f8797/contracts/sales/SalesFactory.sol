// "SPDX-License-Identifier: UNLICENSED"
pragma solidity 0.6.12;

import "../interfaces/IAdmin.sol";

contract SalesFactory {

    // Admin contract
    IAdmin public admin;
    // Allocation staking contract address
    address public allocationStaking;
    // Collateral contract address
    address public collateral;
    // Official sale creation flag
    mapping (address => bool) public isSaleCreatedThroughFactory;
    // Expose so query can be possible only by position as well
    address [] public allSales;
    // Latest sale implementation contract address
    address implementation;

    // Events
    event SaleDeployed(address saleContract);
    event ImplementationChanged(address implementation);
    event AllocationStakingSet(address allocationStaking);

    // Restricting calls only to sale admin
    modifier onlyAdmin {
        require(admin.isAdmin(msg.sender), "Only Admin can deploy sales");
        _;
    }

    constructor (address _adminContract, address _allocationStaking, address _collateral) public {
        admin = IAdmin(_adminContract);
        allocationStaking = _allocationStaking;
        emit AllocationStakingSet(allocationStaking);
        collateral = _collateral;
    }

    /// @notice     Set allocation staking contract address
    function setAllocationStaking(address _allocationStaking) external onlyAdmin {
        require(_allocationStaking != address(0));
        allocationStaking = _allocationStaking;
    }

    /// @notice     Admin function to deploy a new sale
    function deploySale()
    external
    onlyAdmin
    {
        // Deploy sale clone
        address sale;
        // Inline assembly works only with local vars
        address imp = implementation;

        // solhint-disable-next-line no-inline-assembly
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, 0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000)
            mstore(add(ptr, 0x14), shl(0x60, imp))
            mstore(add(ptr, 0x28), 0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000)
            sale := create(0, ptr, 0x37)
        }

        // Require that sale was created
        require(sale != address(0), "Sale creation failed");

        // Initialize sale
        (bool success, ) = sale.call(abi.encodeWithSignature("initialize(address,address,address)", address(admin), allocationStaking, collateral));
        require(success, "Initialization failed.");

        // Mark sale as created through official factory
        isSaleCreatedThroughFactory[sale] = true;
        // Add sale to allSales
        allSales.push(sale);

        // Emit relevant event
        emit SaleDeployed(sale);
    }

    /// @notice     Function to return number of pools deployed
    function getNumberOfSalesDeployed() external view returns (uint) {
        return allSales.length;
    }

    /// @notice     Get most recently deployed sale
    function getLastDeployedSale() external view returns (address) {
        if(allSales.length > 0) {
            // Return the sale address
            return allSales[allSales.length - 1];
        }
        return address(0);
    }

    /// @notice     Function to get all sales between indexes
    function getAllSales(uint startIndex, uint endIndex) external view returns (address[] memory) {
        // Require valid index input
        require(endIndex > startIndex, "Invalid index range.");

        // Create new array for sale addresses
        address[] memory sales = new address[](endIndex - startIndex);
        uint index = 0;

        // Fill the array with sale addresses
        for(uint i = startIndex; i < endIndex; i++) {
            sales[index] = allSales[i];
            index++;
        }

        return sales;
    }

    /// @notice     Function to set the latest sale implementation contract
    function setImplementation(address _implementation) external onlyAdmin {
        require(
            _implementation != implementation,
            "Given implementation is same as current."
        );
        implementation = _implementation;
        emit ImplementationChanged(implementation);
    }
}
