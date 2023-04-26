pragma solidity ^0.4.24;

import "./BasicProjectWallet.sol";

contract ProjectWalletFactory {

  /**
   * @dev Create a new wallet
   * @param _token address The ixo token address
   * @param _authoriser address The address of the contract that
   * @param _name bytes32 The project did
   */
    function createWallet(address _token, address _authoriser, bytes32 _name) public returns (address) {
        require(_name[0] != 0, "Invalid name");
        address wallet = new BasicProjectWallet(_token, _authoriser, _name);
        return wallet;
    }
}


