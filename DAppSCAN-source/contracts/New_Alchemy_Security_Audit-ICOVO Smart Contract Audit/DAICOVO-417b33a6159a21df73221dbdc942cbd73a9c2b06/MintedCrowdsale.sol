pragma solidity ^0.4.18;
//SWC-135-Code With No Effects:L1-28
/**
 * Copyright (c) 2016 Smart Contract Solutions, Inc.
 * Released under the MIT license.
 * https://github.com/OpenZeppelin/openzeppelin-solidity/blob/master/LICENSE
*/

import "../Crowdsale.sol";
import "../../token/extentions/MintableToken.sol";


/**
 * @title MintedCrowdsale
 * @dev Extension of Crowdsale contract whose tokens are minted in each purchase.
 * Token ownership should be transferred to MintedCrowdsale for minting. 
 */
contract MintedCrowdsale is Crowdsale {

  /**
   * @dev Overrides delivery by minting tokens upon purchase.
   * @param _beneficiary Token purchaser
   * @param _tokenAmount Number of tokens to be minted
   */
  function _deliverTokens(address _beneficiary, uint256 _tokenAmount) internal {
    require(MintableToken(token).mint(_beneficiary, _tokenAmount));
  }
}
