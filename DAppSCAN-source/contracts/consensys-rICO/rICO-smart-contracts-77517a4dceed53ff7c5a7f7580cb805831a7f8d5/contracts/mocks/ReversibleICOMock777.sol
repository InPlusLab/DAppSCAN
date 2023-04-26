/*
 * source       https://github.com/mickys/rico-poc/
 * @name        RICO
 * @package     rico-poc
 * @author      Micky Socaci <micky@nowlive.ro>
 * @license     MIT
*/

pragma solidity ^0.5.0;

import './ReversibleICOMock.sol';

contract ReversibleICOMock777 is ReversibleICOMock {

    mapping( address => uint256 ) public balances;

    function setreservedTokenAmount(address wallet, uint256 _balance) external {
        balances[wallet] = _balance;
    }

    function getParticipantReservedTokens(address wallet) public view returns (uint256) {
        return balances[wallet];
    }

    function tokensReceived(
        address operator,
        address from,
        address to,
        uint256 amount,
        bytes calldata userData,
        bytes calldata operatorData
    )
        external
        // solium-disable-next-line no-empty-blocks
    {
        // Rico should only receive tokens from the Rico Token Tracker.
        // any other transaction should revert
    }

}