pragma solidity ^0.5.16;
pragma experimental ABIEncoderV2;

/**
 * This is a contract allowing to batch execute contract calls or
 * contract queries.
 */
contract TxnAggregator {

  /*
  * TO DO:
  *   - Put into seperate repo
  */

  struct ContractCall {
    address dest; // Contract to call
    bytes data;   // Calldata to pass to contract
  }

  /***********************************|
  |         BATCH TRANSACTIONS        |
  |__________________________________*/

  event Error(uint256 tx_id, bytes error);

  /**
   * @notice Will execute transactions with possibly different contracts
   * @param _txns    ContractCall struct array containing all the txns and target contract
   * @param _revert  To revert if a txn fail or to log the error
   */
  function executeTxns(ContractCall[] calldata _txns, bool _revert) external {
    // Execute all txns
    for (uint256 i = 0; i < _txns.length; i++) {
      (bool success, bytes memory resp) = _txns[i].dest.call(_txns[i].data);
      if (!success) {
        // Will either revert on error or log it
        if (_revert) {
          revert(string(resp));
        } else {
          emit Error(i, resp);
        }
      }
    }
  }

  /**
   * @notice Will execute transactions calling _contract
   * @param _contract Target contract that txns are calling
   * @param _txns     Array containing encoded function calls to _contract
   * @param _revert   To revert if a txn fail or to log the error
   */
  function singleContract_executeTxns(address _contract, bytes[] calldata _txns, bool _revert) external {
    // Execute all txns
    for (uint256 i = 0; i < _txns.length; i++) {
      (bool success, bytes memory resp) = _contract.call(_txns[i]);
      if (!success) {
        // Will either revert on error or log it
        if (_revert) {
          revert(string(resp));
        } else {
          emit Error(i, resp);
        }
      }
    }
  }

  /***********************************|
  |           BATCH QUERIES           |
  |__________________________________*/

  /**
   * @notice Will call functions to retrieve data calling _contract
   * @param _txns ContractCall struct array containing all the queries data and target contract
   */
  function viewTxns(ContractCall[] calldata _txns) external view returns (bytes[] memory) {
    // Declaration
    bool success;
    uint256 n_txns = _txns.length;
    bytes[] memory responses = new bytes[](n_txns);

    // Execute all txns
    for (uint256 i = 0; i < n_txns; i++) {
      (success, responses[i]) = _txns[i].dest.staticcall(_txns[i].data);
    }
  }
  
}