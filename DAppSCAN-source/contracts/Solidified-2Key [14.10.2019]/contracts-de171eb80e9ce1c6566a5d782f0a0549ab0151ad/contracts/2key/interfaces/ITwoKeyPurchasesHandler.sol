pragma solidity ^0.4.24;
/**
 * @author Nikola Madjarevic
 */
contract ITwoKeyPurchasesHandler {

    function startVesting(
        uint _baseTokens,
        uint _bonusTokens,
        uint _conversionId,
        address _converter
    )
    public;
}
