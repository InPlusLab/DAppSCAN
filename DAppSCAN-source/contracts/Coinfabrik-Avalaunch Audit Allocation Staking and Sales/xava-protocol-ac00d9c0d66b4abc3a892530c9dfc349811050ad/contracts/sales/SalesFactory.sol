// "SPDX-License-Identifier: UNLICENSED"
pragma solidity 0.6.12;

import "../interfaces/IAdmin.sol";
import "./AvalaunchSale.sol";


contract SalesFactory {

    IAdmin public admin;
    address public allocationStaking;

    mapping (address => bool) public isSaleCreatedThroughFactory;

    mapping(address => address) public saleOwnerToSale;
    mapping(address => address) public tokenToSale;

    // Expose so query can be possible only by position as well
    address [] public allSales;

    event SaleDeployed(address saleContract);
    event SaleOwnerAndTokenSetInFactory(address sale, address saleOwner, address saleToken);

    modifier onlyAdmin {
        require(admin.isAdmin(msg.sender), "Only Admin can deploy sales");
        _;
    }

    constructor (address _adminContract, address _allocationStaking) public {
        admin = IAdmin(_adminContract);
        allocationStaking = _allocationStaking;
    }

    // Set allocation staking contract address.
    function setAllocationStaking(address _allocationStaking) public onlyAdmin {
        require(_allocationStaking != address(0));
        allocationStaking = _allocationStaking;
    }


    function deploySale()
    external
    onlyAdmin
    {
        AvalaunchSale sale = new AvalaunchSale(address(admin), allocationStaking);

        isSaleCreatedThroughFactory[address(sale)] = true;
        allSales.push(address(sale));

        emit SaleDeployed(address(sale));
    }

    // Function to set owner and token for the sale
    function setSaleOwnerAndToken(address saleOwner, address saleToken) external {
        require(isSaleCreatedThroughFactory[msg.sender] == true, "setSaleOwnerAndToken: Contract not eligible.");
        require(saleOwnerToSale[saleOwner] == address(0), "Sale owner already set.");
        require(tokenToSale[saleToken] == address(0), "Sale token already set.");

        // Set owner of the sale.
        saleOwnerToSale[saleOwner] = msg.sender;
        // Set token to sale
        tokenToSale[saleToken] = msg.sender;
        // Emit event
        emit SaleOwnerAndTokenSetInFactory(msg.sender, saleOwner, saleToken);
    }

    // Function to return number of pools deployed
    function getNumberOfSalesDeployed() external view returns (uint) {
        return allSales.length;
    }

    // Function
    function getLastDeployedSale() external view returns (address) {
        //
        if(allSales.length > 0) {
            return allSales[allSales.length - 1];
        }
        return address(0);
    }


    // Function to get all sales
    function getAllSales(uint startIndex, uint endIndex) external view returns (address[] memory) {
        require(endIndex > startIndex, "Bad input");

        address[] memory sales = new address[](endIndex - startIndex);
        uint index = 0;

        for(uint i = startIndex; i < endIndex; i++) {
            sales[index] = allSales[i];
            index++;
        }

        return sales;
    }

}
