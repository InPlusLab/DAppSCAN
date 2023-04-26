pragma solidity ^0.4.24;

import "../utils/Ownable.sol";
import "./ProjectWalletFactory.sol";
import "../token/IxoERC20Token.sol";

contract ProjectWalletRegistry is Ownable {

    address private token;
    address private authoriser;
    address private factory;
    mapping(bytes32 => address) private wallets;

  /**
   * @dev Constructor
   * @param _token address The ixo token address
   * @param _authoriser address The address of the contract that
   * @param _factory address The address of the contract to create project Wallets
   */
    constructor(address _token, address _authoriser, address _factory) public {
        token = _token;
        authoriser = _authoriser;
        factory = _factory;
    }

  /**
   * @dev Sets the factory
   * @param _factory address The address of the contract to create project Wallets
   */
    function setFactory(address _factory) public onlyOwner {
        require(factory != address(0), "Invalid factory");
        factory = _factory;
    }

  /**
   * @dev Ensures a Wallet either exists or one is created
   * @param _name bytes32 The project did
   */
    function ensureWallet(bytes32 _name) public returns (address) {
        require(_name[0] != 0, "Invalid name");
        if(wallets[_name] == address(0)) {
            _createWallet(_name);
        }
        address wallet = wallets[_name];
        return wallet;
    }

  /**
   * @dev Returns the wallet address of the project
   * @param _name bytes32 The project did
   */
    function walletOf(bytes32 _name) public view returns (address) {
        return wallets[_name];
    }

  /**
   * @dev Gets the factory to create a new wallet
   * @param _name bytes32 The project did
   */
    function _createWallet (bytes32 _name) internal {
        address newWallet = ProjectWalletFactory(factory).createWallet(token, authoriser, _name);
        wallets[_name] = newWallet;
    } 
}