// SPDX-License-Identifier: BSD 3-Clause

pragma solidity ^0.6.10;

import "./Administratable.sol";

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

//ORG CONTRACT
/**
 * @title Org
 * @author rheeger
 * @notice Org is a contract that serves as a smart wallet for US nonprofit
 * organizations. It holds the organization's federal Tax ID number as taxID, 
 * and allows for an address to submit a Claim struct to the contract whereby 
 * the organization can direct recieved grant awards from Endaoment Funds.
 */
contract Org is Administratable {
    using SafeMath for uint256;

// ========== STATE VARIABLES ==========
    
    struct Claim {
        string firstName;
        string lastName;
        string eMail;
        address desiredWallet;
        bool filesSubmitted;
    }

    uint public taxId;
    address public orgWallet;
    Claim[] public claims;
    event cashOutComplete(uint cashOutAmount);


// ========== CONSTRUCTOR ==========    
    
    /**
    * @notice Create new Organization Contract
    * @param ein The U.S. Tax Identification Number for the Organization
    * @param adminContractAddress Contract Address for Endaoment Admin
    */
    constructor(uint ein, address adminContractAddress) public onlyAdminOrRole(adminContractAddress, IEndaomentAdmin.Role.ORG_FACTORY){
        taxId = ein;
    }

// ========== Org Management & Info ==========
    
    /**
     * @notice Create Organization Claim
     * @param  fName First name of Administrator
     * @param  lName Last name of Administrator
     * @param  fSub Information Submitted successfully.
     * @param  eMail Email contact for Organization Administrator.
     * @param  orgAdminAddress Wallet address of Organization's Administrator.
     */
    function claimRequest(string memory fName, string memory lName, bool fSub, string memory eMail, address orgAdminAddress) public {
        require (fSub == true);
        require (msg.sender == orgAdminAddress);
        
        Claim memory newClaim = Claim({
            firstName: fName,
            lastName: lName,
            eMail: eMail,
            desiredWallet: msg.sender,
            filesSubmitted: true
        });

        claims.push(newClaim);
    }

    /**
     * @notice Approving Organization Claim 
     * @param  index Index value of Claim.
     * @param  index Index value of Claim.
     * @param adminContractAddress Contract Address for Endaoment Admin
     */
    function approveClaim(uint index, address adminContractAddress) public onlyAdminOrRole(adminContractAddress, IEndaomentAdmin.Role.REVIEWER){
        Claim storage claim = claims[index]; 
        
        setOrgWallet(claim.desiredWallet, adminContractAddress);
    }

    /**
     * @notice Cashing out Organization Contract 
     * @param  desiredWithdrawlAddress Destination for withdrawl
     * @param tokenAddress Stablecoin address of desired token withdrawl
     * @param adminContractAddress Contract Address for Endaoment Admin
     */
    function cashOutOrg(address desiredWithdrawlAddress, address tokenAddress, address adminContractAddress) public onlyAdminOrRole(adminContractAddress, IEndaomentAdmin.Role.ACCOUNTANT){
        ERC20 token = ERC20(tokenAddress);
        uint256 cashOutAmount = token.balanceOf(address(this));

        token.transfer(desiredWithdrawlAddress, cashOutAmount);
        emit cashOutComplete(cashOutAmount);
    }

    function setOrgWallet(address providedWallet, address adminContractAddress) public onlyAdminOrRole(adminContractAddress, IEndaomentAdmin.Role.REVIEWER){
        orgWallet = providedWallet;
    }

     function getTokenBalance(address tokenAddress) public view returns (uint) {
            ERC20 t = ERC20(tokenAddress);
            uint256 bal = t.balanceOf(address(this));

        return bal;
     }

       function getClaimsCount() public view returns (uint) {
        return claims.length;
    }

}
