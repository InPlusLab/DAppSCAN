pragma solidity ^0.4.24;

import "../utils/Ownable.sol";
import "./ProjectWallet.sol";

contract ProjectWalletAuthoriser is Ownable {

    address private authoriser;

    /**
    * @dev Throws if called by any account other than the authoriser.
    */
    modifier onlyAuthoriser() {
        require(msg.sender == authoriser, "Permission denied");
        _;
    }

    function setAuthoriser(address _authoriser) public onlyOwner returns (bool)
    {
        authoriser = _authoriser;
    }

  /**
   * @dev Transfer the amount of tokens from the spender to the receiver.
   * @param _sender The address which will spend the funds.
   * @param _receiver The address which will receiver the funds.
   * @param _amt The amount of tokens to send.
   */
    function transfer(
        address _sender, 
        address _receiver, 
        uint256 _amt
    )
    public onlyAuthoriser
    returns (bool)
    {
        // SWC-104-Unchecked Call Return Value: L38
        ProjectWallet(_sender).transfer(_receiver, _amt);
    }

}


