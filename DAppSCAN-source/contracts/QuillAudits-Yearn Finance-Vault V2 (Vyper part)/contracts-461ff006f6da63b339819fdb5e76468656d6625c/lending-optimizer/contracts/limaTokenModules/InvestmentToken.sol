pragma solidity ^0.6.2;

import {
    OwnableUpgradeSafe
} from "@openzeppelin/contracts-ethereum-package/contracts/access/Ownable.sol";
import {AddressArrayUtils} from "../library/AddressArrayUtils.sol";


contract InvestmentToken is OwnableUpgradeSafe {
    using AddressArrayUtils for address[];
    address[] public investmentTokens;

    function isInvestmentToken(address _investmentToken)
        public
        view
        returns (bool)
    {
        return investmentTokens.contains(_investmentToken);
    }

    function removeInvestmentToken(address _investmentToken)
        external
        onlyOwner
    {
        investmentTokens = investmentTokens.remove(_investmentToken);
    }

    function addInvestmentToken(address _investmentToken) external onlyOwner {
        investmentTokens.push(_investmentToken);
    }
}
