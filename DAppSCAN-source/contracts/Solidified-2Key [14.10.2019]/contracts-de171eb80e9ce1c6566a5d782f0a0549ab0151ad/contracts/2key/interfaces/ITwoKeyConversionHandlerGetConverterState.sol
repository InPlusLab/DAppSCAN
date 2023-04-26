pragma solidity ^0.4.24;

import "../TwoKeyConverterStates.sol";
/**
 * @author Nikola Madjarevic
 * Created at 2/20/19
 */
contract ITwoKeyConversionHandlerGetConverterState {
    function getStateForConverter(address _converter) public view returns (bytes32);
}
