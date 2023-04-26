pragma solidity ^0.4.15;

/**
 * Authored by https://www.coinfabrik.com/
 */

import "./GenericCrowdsale.sol";
import "./CrowdsaleToken.sol";
import "./LostAndFoundToken.sol";
import "./TokenTranchePricing.sol";

// This contract has the sole objective of providing a sane concrete instance of the Crowdsale contract.
contract Crowdsale is GenericCrowdsale, LostAndFoundToken, TokenTranchePricing {
  //initial supply in 400k, sold tokens from initial minting
  uint8 private constant token_decimals = 18;
  uint private constant token_initial_supply = 1575 * (10 ** 5) * (10 ** uint(token_decimals));
  bool private constant token_mintable = true;
  uint private constant sellable_tokens = 525 * (10 ** 5) * (10 ** uint(token_decimals));

  /**
   * Constructor for the crowdsale.
   * Normally, the token contract is created here. That way, the minting, release and transfer agents can be set here too.
   *
   * @param team_multisig Address of the multisignature wallet of the team that will receive all the funds contributed in the crowdsale.
   * @param start Block number where the crowdsale will be officially started. It should be greater than the block number in which the contract is deployed.
   * @param end Block number where the crowdsale finishes. No tokens can be sold through this contract after this block.
   * @param token_retriever Address that will handle tokens accidentally sent to the token contract. See the LostAndFoundToken and CrowdsaleToken contracts for further details.
   * @param init_tranches List of serialized tranches. See config.js and TokenTranchePricing for further details.
   */
  function Crowdsale(address team_multisig, uint start, uint end, address token_retriever, uint[] init_tranches)
  GenericCrowdsale(team_multisig, start, end) TokenTranchePricing(init_tranches) public {
    require(end == tranches[tranches.length.sub(1)].end);
    // Testing values
    token = new CrowdsaleToken(token_initial_supply, token_decimals, team_multisig, token_mintable, token_retriever);

    // Set permissions to mint, transfer and release
    token.setMintAgent(address(this), true);
    token.setTransferAgent(address(this), true);
    token.setReleaseAgent(address(this));

    // Tokens to be sold through this contract
    token.mint(address(this), sellable_tokens);
    // We don't need to mint anymore during the lifetime of the contract.
    token.setMintAgent(address(this), false);
  }

  //Token assignation through transfer
  function assignTokens(address receiver, uint tokenAmount) internal {
    token.transfer(receiver, tokenAmount);
  }

  //Token amount calculation
  function calculateTokenAmount(uint weiAmount, address) internal constant returns (uint weiAllowed, uint tokenAmount) {
    uint tokensPerWei = getCurrentPrice(tokensSold);
    uint maxAllowed = sellable_tokens.sub(tokensSold).div(tokensPerWei);
    weiAllowed = maxAllowed.min256(weiAmount);

    if (weiAmount < maxAllowed) {
      tokenAmount = tokensPerWei.mul(weiAmount);
    }
    // With this case we let the crowdsale end even when there are rounding errors due to the tokens to wei ratio
    else {
      tokenAmount = sellable_tokens.sub(tokensSold);
    }
  }

  // Implements the criterion of the funding state
  function isCrowdsaleFull() internal constant returns (bool) {
    return tokensSold >= sellable_tokens;
  }

  /**
   * This function decides who handles lost tokens.
   * Do note that this function is NOT meant to be used in a token refund mechanism.
   * Its sole purpose is determining who can move around ERC20 tokens accidentally sent to this contract.
   */
  function getLostAndFoundMaster() internal constant returns (address) {
    return owner;
  }

  // Extended to transfer unused funds to team team_multisig and release the token
  function finalize() public inState(State.Success) onlyOwner stopInEmergency {
    token.releaseTokenTransfer();
    uint unsoldTokens = token.balanceOf(address(this));
    token.transfer(multisigWallet, unsoldTokens);
    super.finalize();
  }

  //Change the the starting time in order to end the presale period early if needed.
  function setStartingTime(uint startingTime) public onlyOwner inState(State.PreFunding) {
    require(startingTime > block.timestamp && startingTime < endsAt);
    startsAt = startingTime;
  }

  //Change the the ending time in order to be able to finalize the crowdsale if needed.
  function setEndingTime(uint endingTime) public onlyOwner notFinished {
    require(endingTime > block.timestamp && endingTime > startsAt);
    endsAt = endingTime;
  }

  /**
   * Override to reject calls unless the crowdsale is finalized or
   *  the token contract is not the one corresponding to this crowdsale
   */
  function enableLostAndFound(address agent, uint tokens, EIP20Token token_contract) public {
    // Either the state is finalized or the token_contract is not this crowdsale token
    require(address(token_contract) != address(token) || getState() == State.Finalized);
    super.enableLostAndFound(agent, tokens, token_contract);
  }
}