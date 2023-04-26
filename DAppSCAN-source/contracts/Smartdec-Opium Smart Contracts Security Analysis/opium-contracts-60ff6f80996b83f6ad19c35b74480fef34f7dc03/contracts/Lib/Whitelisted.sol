pragma solidity ^0.5.4;

/// @title Opium.Lib.Whitelisted contract implements whitelist with modifier to restrict access to only whitelisted addresses
contract Whitelisted {
    // Whitelist array
    address[] internal whitelist;

    /// @notice This modifier restricts access to functions, which could be called only by whitelisted addresses
    modifier onlyWhitelisted() {
        // Allowance flag
        bool allowed = false;

        // Going through whitelisted addresses array
        for (uint256 i = 0; i < whitelist.length; i++) {
            // If `msg.sender` is met within whitelisted addresses, raise the flag and exit the loop
            if (whitelist[i] == msg.sender) {
                allowed = true;
                break;
            }
        }

        // Check if flag was raised
        require(allowed, "Only whitelisted allowed");
        _;
    }

    /// @notice Getter for whitelisted addresses array
    /// @return Array of whitelisted addresses
    function getWhitelist() public view returns (address[] memory) {
        return whitelist;
    }
}
