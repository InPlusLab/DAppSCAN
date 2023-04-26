pragma solidity ^0.4.10;

import '../common/Manageable.sol';
import './BCSCrowdsale.sol';
import './BCSTokenCrowdsale.sol';
import '../token/BCSToken.sol';
import '../token/TokenPool.sol';
import '../token/ReturnableToken.sol';
import './TrancheWallet.sol';

/**@dev Crowdsale controller, contains information about pretge and tge stages and holds token */
contract BCSCrowdsaleController is Manageable {

    // uint256 constant TOKEN_CAP = 10000000; // token cap, according to whitepaper   
    // uint256 constant TOKEN_DEV_RESERVE_PCT = 20; //reserved to dev team, according to whitepaper
    // uint256 constant TOKEN_MISC_RESERVE_PCT = 5; //reserved to advisors etc., according to whitepaper
    // uint256 constant TOKEN_PRETGE_SALE_PCT = 12; //we are selling this % during pretge   
    // uint256 constant TGE_TOKENS_FOR_ONE_ETHER = 100;    
    // uint256 constant DEV_TOKENS_LOCKED_DAYS = 365;
    // uint256 constant TRANCHE_AMOUNT_PCT = 8;
    // uint256 constant TRANCHE_PERIOD_DAYS = 30;
    // uint256 constant FUNDS_COMPLETE_UNLOCK_DAYS = 365;
    // uint8 constant TOKEN_DECIMALS = 18;
    
    // BCSToken public token;
    
    // BCSCrowdsale public preTgeSale;
    // BCSTokenCrowdsale public tgeSale;    

    // TokenPool preTgePool;
    // TokenPool tgePool;

    // //LockableWallet public beneficiaryWallet;    
    // address public devTeamTokenStorage;
    // address public miscTokenStorage;

     function BCSCrowdsaleController() {}

    // /**@dev Step 0. Initialize beneficiaries */
    // function initBeneficiaries(address _beneficiary, address _devTeamTokenStorage, address _miscTokenStorage) managerOnly {
    //     require(address(_beneficiary) != 0 && _devTeamTokenStorage != 0 && _miscTokenStorage != 0);

    //     devTeamTokenStorage = _devTeamTokenStorage;
    //     miscTokenStorage = _miscTokenStorage;
    //     beneficiaryWallet = new TrancheWallet(_beneficiary, TRANCHE_PERIOD_DAYS, TRANCHE_AMOUNT_PCT);        
    // }

    // /**@dev Step 1.1. Create token and token pools*/
    // function createToken() managerOnly {
    //     require(address(token) == 0x0);

    //     token = new BCSToken(TOKEN_CAP, TOKEN_DECIMALS);        
    //     token.setManager(msg.sender, true);

    //     uint256 tokenSupply = token.totalSupply();
    //     token.transfer(devTeamTokenStorage, tokenSupply * TOKEN_DEV_RESERVE_PCT / 100);
    //     token.transfer(miscTokenStorage, tokenSupply * TOKEN_MISC_RESERVE_PCT / 100);
        
    //     preTgePool = new TokenPool(token);
    //     tgePool = TokenPool(token);

    //     token.transfer(preTgePool, tokenSupply * TOKEN_PRETGE_SALE_PCT / 100);

    //     token.lockTransferFor(devTeamTokenStorage, DEV_TOKENS_LOCKED_DAYS);  //lock dev's tokens        
    // }

    // /**@dev Step 1.2. Reserve some tokens for bancor protocol */
    // function reserveForBancor(address reserveAddress, uint256 reservePct) managerOnly {
    //     token.setReserved(reserveAddress, true);
    //     token.transfer(reserveAddress, token.totalSupply() * reservePct / 100);
    // }

    // /**@dev Step 2.1. Approves angel sale to sell tokens from pre-tge pool */
    // function setAngelSale(address angelSale) managerOnly {
    //     preTgePool.setTrustee(angelSale, true);
    // }

    // /**@dev Step 2.2. Approves preTge sale to sell tokens */
    // function setPretge(BCSCrowdsale newPreTge) managerOnly {
    //     preTgeSale = newPreTge;        
    //     preTgePool.setTrustee(preTgeSale, true);
    // }    

    // /**@dev Step 3. Withdraw funds from pretge */
    // function finalizePretge() managerOnly {
    //     require(preTgeSale.getState() == BCSCrowdsale.State.FinishedSuccess);
    //     require(preTgeSale.balance > 0);
                
    //     preTgeSale.transferToBeneficiary();
    // }

    // /**@dev Step 4.1. Create tge crowdsale */
    // function setTge(BCSTokenCrowdsale newTge) managerOnly {
    //     tgeSale = BCSTokenCrowdsale(newTge);

    //     preTgePool.returnTokensTo(this);
    //     token.transfer(tgePool, token.balanceOf(this));

    //     tgePool.setTrustee(newTge, true);
    // }

    // /**@dev Step 4.2. Allocate tokens for bonus tokens exchange */
    // function allocateBonusTokens(ReturnableToken bonusToken) managerOnly {
    //     tgeSale.setReturnableToken(bonusToken);
    //     token.transfer(tgeSale, bonusToken.totalSupply());
    // }

    // /**@dev Step 5. Withdraw funds from tge and burn the rest of tokens*/
    // function finalizeTge() managerOnly {        
    //     require(tgeSale.getState() == BCSCrowdsale.State.FinishedSuccess);        

    //     tgeSale.transferToBeneficiary(); 
    //     tgeSale.returnUnclaimedTokens();
        
    //     tgePool.returnTokensTo(this);        
        
    //     token.burn(token.balanceOf(this));

    //     beneficiaryWallet.lock(FUNDS_COMPLETE_UNLOCK_DAYS);        
    //     //token.transferOwnership(0x0);        
    // }    

    /***********************************************************************************************
    * temp dev methods 
    ***********************************************************************************************/    
    // function setToken(address newToken) managerOnly {
    //     token = BCSToken(newToken);
    //     token.transferOwnership(this);
    // }
    // function setWallet(address newWallet) managerOnly {
    //     beneficiaryWallet = LockableWallet(newWallet);
    //     beneficiaryWallet.transferOwnership(this);
    // }
}   