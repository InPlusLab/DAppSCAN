pragma solidity ^0.4.24;

import "./ProjectWallet.sol";
import "../token/ERC20.sol";

contract BasicProjectWallet is ProjectWallet {

    address private token;
    address private authoriser;
    bytes32 public name;

  /**
   * @dev Constructor
   * @param _token address The ixo token address
   * @param _authoriser address The address of the contract that
   * @param _name bytes32 The project name
   */
    constructor(address _token, address _authoriser, bytes32 _name) public {
        token = _token;
        authoriser = _authoriser;
        name = _name;
    }

    /**
    * @dev Throws if called by any account other than the authoriser.
    */
    modifier onlyAuthoriser() {
        require(msg.sender == authoriser, "Permission denied");
        _;
    }

  /**
   * @dev Transfer tokens to the receiver
   * @param _receiver The address which will receive the funds.
   * @param _amt The amount of tokens to transfer.
   */
    function transfer(
        address _receiver,
        uint256 _amt
    )
    public onlyAuthoriser
    returns (bool)
    {
        ERC20(token).transfer(_receiver, _amt);
    }

}


