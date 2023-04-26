pragma solidity ^0.4.23;

contract MintedCappedTokenMockUtils {

  function getSelectors() public pure returns (bytes4[] memory selectors) {
    selectors = new bytes4[](23);

    selectors[0] = this.initializeCrowdsale.selector;
    selectors[1] = this.finalizeCrowdsale.selector;
    selectors[2] = this.updateTierMinimum.selector;
    selectors[3] = this.createCrowdsaleTiers.selector;
    selectors[4] = this.whitelistMultiForTier.selector;
    selectors[5] = this.updateTierDuration.selector;

    selectors[6] = this.initCrowdsaleToken.selector;
    selectors[7] = this.setTransferAgentStatus.selector;
    selectors[8] = this.updateMultipleReservedTokens.selector;
    selectors[9] = this.removeReservedTokens.selector;
    selectors[10] = this.distributeReservedTokens.selector;
    selectors[11] = this.finalizeCrowdsaleAndToken.selector;
    selectors[12] = this.finalizeAndDistributeToken.selector;

    selectors[13] = this.buy.selector;

    selectors[14] = bytes4(keccak256('transfer(address,uint256)'));
    selectors[15] = this.transferFrom.selector;
    selectors[16] = this.approve.selector;
    selectors[17] = this.increaseApproval.selector;
    selectors[18] = this.decreaseApproval.selector;

    selectors[19] = this.setBalance.selector;
    selectors[20] = this.unlockToken.selector;
    selectors[21] = this.setTransferAgent.selector;
    selectors[22] = this.setTotalSold.selector;
  }

  // Mock
  function setBalance(address, uint) public pure returns (bytes) { return msg.data; }
  function unlockToken() public pure returns (bytes) { return msg.data; }
  function setTransferAgent(address, bool) public pure returns (bytes) { return msg.data; }
  function setTotalSold(uint) public pure returns (bytes) { return msg.data; }

  // SaleManager
  function initializeCrowdsale() public pure returns (bytes) { return msg.data; }
  function finalizeCrowdsale() public pure returns (bytes) { return msg.data; }
  function updateTierMinimum(uint, uint) public pure returns (bytes) { return msg.data; }
  function createCrowdsaleTiers(bytes32[], uint[], uint[], uint[], uint[], bool[], bool[])
      public pure returns (bytes) { return msg.data; }
  function whitelistMultiForTier(uint, address[], uint[], uint[])
      public pure returns (bytes) { return msg.data; }
  function updateTierDuration(uint, uint) public pure returns (bytes) { return msg.data; }

  // TokenManager
  function initCrowdsaleToken(bytes32, bytes32, uint) public pure returns (bytes) { return msg.data; }
  function setTransferAgentStatus(address, bool) public pure returns (bytes) { return msg.data; }
  function updateMultipleReservedTokens(address[], uint[], uint[], uint[])
      public pure returns (bytes) { return msg.data; }
  function removeReservedTokens(address) public pure returns (bytes) { return msg.data; }
  function distributeReservedTokens(uint) public pure returns (bytes) { return msg.data; }
  function finalizeCrowdsaleAndToken() public pure returns (bytes) { return msg.data; }
  function finalizeAndDistributeToken() public pure returns (bytes) { return msg.data; }

  // Sale
  function buy() public pure returns (bytes) { return msg.data; }

  // Token
  function transfer(address, uint) public pure returns (bytes) { return msg.data; }
  function transferFrom(address, address, uint) public pure returns (bytes) { return msg.data; }
  function approve(address, uint) public pure returns (bytes) { return msg.data; }
  function increaseApproval(address, uint) public pure returns (bytes) { return msg.data; }
  function decreaseApproval(address, uint) public pure returns (bytes) { return msg.data; }

  function init(
    address, uint, bytes32, uint, uint, uint, uint, bool, bool, address
  ) public pure returns (bytes memory) {
    return msg.data;
  }


}
