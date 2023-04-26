pragma solidity ^0.5.2;

import '../storage/interfaces/IDFStore.sol';
import '../utility/DSAuth.sol';

contract DFSetting is DSAuth {
    IDFStore public dfStore;

    enum ProcessType {
        CT_DEPOSIT,
        CT_DESTROY,
        CT_CLAIM,
        CT_WITHDRAW
    }

    enum TokenType {
        TT_DF,
        TT_USDX
    }

    constructor (address _dfStore) public {
        dfStore = IDFStore(_dfStore);
    }

    // set commission rate.
    function setCommissionRate(ProcessType ct, uint rate) public auth {
        dfStore.setFeeRate(uint(ct), rate);
    }

    // set type of token.
    function setCommissionToken(TokenType ft, address _tokenID) public auth {
        dfStore.setTypeToken(uint(ft), _tokenID);
    }

    // set token's medianizer.
    function setCommissionMedian(address _tokenID, address _median) public auth {
        dfStore.setTokenMedian(_tokenID, _median);
    }

    // set destroy threshold of minimal usdx.
    function setDestroyThreshold(uint _amount) public auth {
        dfStore.setMinBurnAmount(_amount);
    }

    // update mint section material.
    function updateMintSection(address[] memory _wrappedTokens, uint[] memory _weight) public auth {
        dfStore.setSection(_wrappedTokens, _weight);
    }
}
