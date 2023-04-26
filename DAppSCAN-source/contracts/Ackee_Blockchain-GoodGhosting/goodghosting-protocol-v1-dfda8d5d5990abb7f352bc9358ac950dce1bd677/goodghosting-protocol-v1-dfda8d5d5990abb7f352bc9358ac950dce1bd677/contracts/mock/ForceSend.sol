pragma solidity 0.6.11;

// Used for sending ETH to DAI Unlocked Account on Test Cases (when forking from live network)
contract ForceSend {
    function go(address payable victim) external payable {
        selfdestruct(victim);
    }
}