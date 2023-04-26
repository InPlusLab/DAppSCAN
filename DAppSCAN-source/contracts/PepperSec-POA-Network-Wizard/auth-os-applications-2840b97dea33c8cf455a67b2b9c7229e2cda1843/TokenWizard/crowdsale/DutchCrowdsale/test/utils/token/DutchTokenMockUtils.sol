pragma solidity ^0.4.23;

contract DutchTokenMockUtils {

  function getSelectors() public pure returns (bytes4[] memory selectors) {
    selectors = new bytes4[](16);

    selectors[0] = this.initializeCrowdsale.selector;
    selectors[1] = this.finalizeCrowdsale.selector;
    selectors[2] = this.updateGlobalMinContribution.selector;
    selectors[3] = this.whitelistMulti.selector;
    selectors[4] = this.setCrowdsaleStartandDuration.selector;
    selectors[5] = this.initCrowdsaleToken.selector;
    selectors[6] = this.setTransferAgentStatus.selector;

    selectors[7] = this.buy.selector;

    selectors[8] = bytes4(keccak256('transfer(address,uint256)'));
    selectors[9] = this.transferFrom.selector;
    selectors[10] = this.approve.selector;
    selectors[11] = this.increaseApproval.selector;
    selectors[12] = this.decreaseApproval.selector;

    selectors[13] = this.setBalance.selector;
    selectors[14] = this.unlockToken.selector;
    selectors[15] = this.setTransferAgent.selector;
  }

  // Mock
  function setBalance(address, uint) public pure returns (bytes) { return msg.data; }
  function unlockToken() public pure returns (bytes) { return msg.data; }
  function setTransferAgent(address, bool) public pure returns (bytes) { return msg.data; }

  // Admin
  function initializeCrowdsale() public pure returns (bytes) { return msg.data; }
  function finalizeCrowdsale() public pure returns (bytes) { return msg.data; }
  function updateGlobalMinContribution(uint) public pure returns (bytes) { return msg.data; }
  function whitelistMulti(address[], uint[], uint[]) public pure returns (bytes) { return msg.data; }
  function setCrowdsaleStartandDuration(uint, uint) public pure returns (bytes) { return msg.data; }
  function initCrowdsaleToken(bytes32, bytes32, uint) public pure returns (bytes) { return msg.data; }
  function setTransferAgentStatus(address, bool) public pure returns (bytes) { return msg.data; }

  // Sale
  function buy() public pure returns (bytes) { return msg.data; }

  // Token
  function transfer(address, uint) public pure returns (bytes) { return msg.data; }
  function transferFrom(address, address, uint) public pure returns (bytes) { return msg.data; }
  function approve(address, uint) public pure returns (bytes) { return msg.data; }
  function increaseApproval(address, uint) public pure returns (bytes) { return msg.data; }
  function decreaseApproval(address, uint) public pure returns (bytes) { return msg.data; }

  function init(
    address, uint, uint, uint, uint, uint, uint, bool, address, bool
  ) public pure returns (bytes memory) {
    return msg.data;
  }
}
