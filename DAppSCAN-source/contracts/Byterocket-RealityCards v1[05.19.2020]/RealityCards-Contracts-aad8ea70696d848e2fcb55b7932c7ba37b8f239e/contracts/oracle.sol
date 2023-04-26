pragma solidity ^0.5.0;

interface IMarket 
{
    function getWinningPayoutNumerator(uint256 _outcome) external view returns (uint256);
}

contract OracleExampleAugur1 {

    // replace with the market's address
    IMarket public market = IMarket(0x34A971cA2fd6DA2Ce2969D716dF922F17aAA1dB0); 

    function getWinnerFromAugurBinaryMarket() public view {
        if (market.getWinningPayoutNumerator(0) > 0) {
            // insert logic for Invalid outcome
        } else if (market.getWinningPayoutNumerator(1) > 0)  {
            // insert logic for Yes outcome
        } else if (market.getWinningPayoutNumerator(2) > 0) {
            // insert logic for No outcome
        } else {
            // insert logic for market not yet settled
        }
    }
}

interface OICash
{
    function deposit(uint256 _amount) external returns (bool);
    function withdraw(uint256 _amount) external returns (bool);
}

contract OracleExampleAugur2 {

    // replace with the current contract address
    OICash public oicash = OICash(0xbD41281dE5E4cA62602ed7c134f46d831A340B78);

    function augurDeposit(uint256 _amount) public {
        require(oicash.deposit(_amount), "Augur deposit failed");
    }

    function augurWithdraw(uint256 _amount) public {
        require(oicash.withdraw(_amount), "Augur withdraw failed");
    }
}

interface IRealitio 
{
    function askQuestion(
        uint256 template_id, 
        string calldata question, 
        address arbitrator, 
        uint32 timeout, 
        uint32 opening_ts, 
        uint256 nonce) 
        external payable returns (bytes32);
    function resultFor(bytes32 question_id) external view returns (bytes32);
    function isFinalized(bytes32 question_id) external view returns (bool);
}

contract OracleExampleRealitio1 {

    // this is the current mainnet address
    IRealitio public realitio = IRealitio(0x325a2e0F3CCA2ddbaeBB4DfC38Df8D19ca165b47);

    // example market data:
    uint256 public template_id = 2; 
    string public question = 
        'Who will win the 2020 US General Election␟"Donald Trump","Joe Biden"␟news-politics␟en_US';
    address public arbitrator = 0xd47f72a2d1d0E91b0Ec5e5f5d02B2dc26d00A14D; // kleros.io mainnet address
    uint32 public timeout = 86400; // one day
    uint32 public opening_ts = 1604448000; // Nov 4th 2020
    uint256 public nonce = 0;

    function _postQuestion() public returns (bytes32) {
        return
            realitio.askQuestion(
            template_id,
            question,
            arbitrator,
            timeout,
            opening_ts,
            nonce
            );
    }
}

contract OracleExampleRealitio2 {

    // this is the current mainnet address
    IRealitio public realitio = IRealitio(0x325a2e0F3CCA2ddbaeBB4DfC38Df8D19ca165b47);

    function getWinnerFromRealitioBinaryMarket(bytes32 _questionId) public view {
        if (realitio.isFinalized(_questionId)) {
            bytes32 _winningOutcome = realitio.resultFor(_questionId);
            uint _winningOutcomeUint = uint(_winningOutcome);
            if (_winningOutcomeUint == 0) {
                // insert logic for the first listed outcome
            } else if (_winningOutcomeUint == 1) {
                // insert logic for the second listed outcome
            } else if (_winningOutcomeUint == ((2**256)-1)) {
                // insert logic for Invalid outcome
            }
        }       
    }
}