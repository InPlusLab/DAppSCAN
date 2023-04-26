// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.7.0;

import {IGlobalAddressesProvider} from "../../../interfaces/GlobalAddressesProvider/IGlobalAddressesProvider.sol";
import {IERC20} from "../../dependencies/openzeppelin/token/ERC20/IERC20.sol";

contract SIGH_Fee_Collector {

    IGlobalAddressesProvider globalAddressesProvider;
    event CollectedFeeTransferred(address tokenAddress,address destination,uint amount, uint remainingBalance);

    modifier onlySIGHFinanceManager {
        address sighFinanceManager =  globalAddressesProvider.getSIGHFinanceManager();
        require( sighFinanceManager == msg.sender, "The caller must be the SIGH FINANCE Manager" );
        _;
    }

    constructor(address globalAddressesProvider_) {
        globalAddressesProvider = IGlobalAddressesProvider(globalAddressesProvider_);
    }

//    #################################################
//    ####### FUNCTION TO TRANSFER COLLECTED FEE ######
//    #################################################

    function transferInstrumentBalance(IERC20 tokenAddress, address destination, uint amount) external onlySIGHFinanceManager returns (bool) {
        uint prevBalance = tokenAddress.balanceOf(address(this));
        require(prevBalance >= amount,'Required balance not available');
        tokenAddress.transfer(destination,amount);
        uint newBalance = tokenAddress.balanceOf(address(this));
        emit CollectedFeeTransferred(address(tokenAddress),destination,amount,newBalance);
        return true;
    }

//    ############################
//    ####### VIEW FUNCTION ######
//    ############################

    function getInstrumentBalance(IERC20 tokenAddress) external returns (uint) {
        return tokenAddress.balanceOf(address(this));
    }

}
