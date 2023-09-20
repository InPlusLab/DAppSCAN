// SWC-135-Code With No Effects: L2
pragma solidity ^0.4.11;


import "./MiniMeToken.sol";


contract REAL is MiniMeToken {
    // @dev REAL constructor just parametrizes the MiniMeIrrevocableVestedToken constructor
    function REAL(address _tokenFactory)
            MiniMeToken(
                _tokenFactory,
                0x0,                         // no parent token
                0,                           // no snapshot block number from parent
                "Real Estate Asset Ledger",  // Token name
                18,                          // Decimals
                "REAL",                      // Symbol
                true                         // Enable transfers
            ) {}
}
