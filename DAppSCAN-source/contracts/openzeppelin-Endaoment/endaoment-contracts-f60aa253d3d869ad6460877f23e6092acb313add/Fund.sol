// SPDX-License-Identifier: BSD 3-Clause

pragma solidity ^0.6.10;

import "./Administratable.sol";
import "./OrgFactory.sol";

// FUND CONTRACT
/**
 * @title Fund
 * @author rheeger
 * @notice Fund is a contract that serves as an on-chain US Donor-Advised Fund.
 * It holds the proceeds of gifted cryptocurrency as ERC20 tokens, 
 * and allows for the manager to submit Grant reccomendations to the contract. 
 * The EndaomentAdmin can then chose to approve the Grant reccomendation, triggering
 * a SafeMath transfer of a 1% fee to the EndaomentAdmin and the remainder to the 
 * recipient Org contract.
 */
contract Fund is Administratable {
    using SafeMath for uint256;

// ========== STATE VARIABLES ==========
    struct Grant {
        string description;
        uint value;
        address recipient;
        bool complete;
    }

    address public manager;
    address public admin;
    mapping(address => bool) public contributors;
    Grant[] public grants;
    uint public totalContributors;

// ========== CONSTRUCTOR ==========
    /**
    * @notice Create new Fund
    * @param creator Address of the Fund's Primary Advisor
    * @param adminContractAddress Address of the EndaomentAdmin contract.
    */
    constructor (address creator, address adminContractAddress) public onlyAdminOrRole(adminContractAddress, IEndaomentAdmin.Role.FUND_FACTORY){
        require(creator != address(0));
        manager = creator;
    }

// ========== Admin Management ==========
    /**
    * @notice Restricts method access to fund's manager
    */
    modifier restricted() {
      require(msg.sender == manager);
      _;
    }

// ========== Fund Management & Info ==========
    /**
    * @notice Change Fund Primary Advisor
    * @param  newManager The address of the new PrimaryAdvisor.
    * @param  adminContractAddress Address of the EndaomentAdmin contract.
    */
    function changeManager (address newManager, address adminContractAddress) public onlyAdminOrRole(adminContractAddress, IEndaomentAdmin.Role.REVIEWER){
        manager = newManager;
    }

    /**
    * @notice Checks recipient of a Grant is an address created by the OrgFactory 
    * @param  recipient The address of the Grant recipient.
    * @param  orgFactoryContractAddress Address of the OrgFactory contract.
    */
    function checkRecipient(address recipient, address orgFactoryContractAddress) public view returns (bool) {
        OrgFactory x = OrgFactory ( orgFactoryContractAddress );

        return x.getAllowedOrg(recipient);
    }

    /**
    * @notice Returns summary of details about the fund [tokenBalance, ethBlance, number of grants, managerAddress]. 
    * @param  tokenAddress The token address of the stablecoin being used by the web-server.
    */
    function getSummary(address tokenAddress) public view returns (uint, uint, uint, address) {
        ERC20 t = ERC20(tokenAddress);
        uint bal = t.balanceOf(address(this));

        return (
            bal,
            address(this).balance,
            grants.length,
            manager
        );
    }

    /**
    * @notice Create new Grant Reccomendation
    * @param  description The address of the Owner.
    * @param  value The value of the grant in base units.
    * @param  recipient The address of the recieving organization's contract.
    * @param  orgFactoryContractAddress Address of the orgFactory Contract.
    */
    function createGrant(string memory description, uint256 value, address recipient, address orgFactoryContractAddress) public restricted {
        require(checkRecipient(recipient, orgFactoryContractAddress) == true);

        Grant memory newGrant = Grant({
            description: description,
            value: value,
            recipient: recipient,
            complete: false
        });

        grants.push(newGrant);
    }
//SWC-107-Reentrancy:L119-134
    /**
    * @notice Approve Grant Reccomendation
    * @param  index This Grant's index position
    * @param  tokenAddress The stablecoin's token address.
    * @param  adminContractAddress Address of the EndaomentAdmin contract.
    */
    function finalizeGrant(uint index, address tokenAddress, address adminContractAddress) public onlyAdminOrRole(adminContractAddress, IEndaomentAdmin.Role.ACCOUNTANT){
        EndaomentAdmin endaomentAdmin = EndaomentAdmin(adminContractAddress);
        admin = endaomentAdmin.getRoleAddress(IEndaomentAdmin.Role.ADMIN);
        Grant storage grant = grants[index];
        require(grant.complete == false);
        ERC20 t = ERC20(tokenAddress);

        //Process fees:
        uint256 fee = (grant.value)/100;
        uint256 finalGrant = (grant.value * 99)/100;
        t.transfer(admin, fee);

        t.transfer(grant.recipient, finalGrant);

        grant.complete = true;
    }

    /**
    * @notice Returns total number of grants submitted to the fund. 
    */
    function getGrantsCount() public view returns (uint) {
        return grants.length;
    }
}
