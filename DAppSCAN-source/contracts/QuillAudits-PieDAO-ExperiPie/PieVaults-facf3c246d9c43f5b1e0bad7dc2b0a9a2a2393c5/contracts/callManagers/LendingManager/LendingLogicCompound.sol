// SPDX-License-Identifier: MIT
pragma experimental ABIEncoderV2;
pragma solidity ^0.7.1;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../interfaces/ILendingLogic.sol";
import "./LendingRegistry.sol";
import "../../interfaces/ICToken.sol";

contract LendingLogicCompound is ILendingLogic {

    LendingRegistry public lendingRegistry;
    bytes32 public constant PROTOCOL = keccak256(abi.encodePacked("Compound"));

    constructor(address _lendingRegistry) {
        lendingRegistry = LendingRegistry(_lendingRegistry);
    }

    function lend(address _underlying, uint256 _amount) external view override returns(address[] memory targets, bytes[] memory data) {
        IERC20 underlying = IERC20(_underlying);

        targets = new address[](3);
        data = new bytes[](3);


        address cToken = lendingRegistry.underlyingToProtocolWrapped(_underlying, PROTOCOL);

        // zero out approval to be sure
        targets[0] = _underlying;
        data[0] = abi.encodeWithSelector(underlying.approve.selector, cToken, 0);

        // Set approval
        targets[1] = _underlying;
        data[1] = abi.encodeWithSelector(underlying.approve.selector, cToken, _amount);

        // Deposit into Compound
        targets[2] = cToken;

        data[2] =  abi.encodeWithSelector(ICToken.mint.selector, _amount);

        return(targets, data);
    }
    function unlend(address _wrapped, uint256 _amount) external view override returns(address[] memory targets, bytes[] memory data) {
        targets = new address[](1);
        data = new bytes[](1);

        targets[0] = _wrapped;
        data[0] = abi.encodeWithSelector(ICToken.redeem.selector, _amount);
        
        return(targets, data);
    }

}