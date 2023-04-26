pragma solidity 0.5.14;

import "../SavingAccount.sol";
import { IController } from "../compound/ICompound.sol";
import "../Accounts.sol";
//import { TokenRegistry } from "../registry/TokenRegistry.sol";
//import { Bank } from "../Bank.sol";
//import "../config/GlobalConfig.sol";

// This file is only for testing purpose only
contract SavingAccountWithController is SavingAccount {

    Accounts.Account public accountVariable;
    //GlobalConfig public globalConfig;
    address comptroller;

    constructor() public {
        // DO NOT ADD ANY LOGIC HERE.
        // THIS IS AN UPGRADABLE CONTRACT
    }

    /**
     * Intialize the contract
     * @param _tokenAddresses list of token addresses
     * @param _cTokenAddresses list of corresponding cToken addresses
     * @param _globalConfig global configuration contract
     * @param _comptroller Compound controller address
     */
    function initialize(
        address[] memory _tokenAddresses,
        address[] memory _cTokenAddresses, 
        //TokenRegistry _tokenRegistry, // can remove
        GlobalConfig _globalConfig,
        address _comptroller
    ) public initializer {
        comptroller = _comptroller;
        super.initialize(_tokenAddresses, _cTokenAddresses, _globalConfig);
    }

    /**
     * Fastfoward for specified block numbers. The block number is synced to compound.
     * @param blocks number of blocks to be forwarded
     */
    function fastForward(uint blocks) public returns (uint) {
        return IController(comptroller).fastForward(blocks);
    }

    /**
     * Get the block number from comound
     */
    function getBlockNumber() internal view returns (uint) {
        return IController(comptroller).getBlockNumber();
    }

    function newRateIndexCheckpoint(address _token) public {
        globalConfig.bank().newRateIndexCheckpoint(_token);
    }

    function getDepositPrincipal(address _token) public view returns (uint256) {
        //TokenRegistry.TokenInfo storage tokenInfo.depositPrincipal = globalConfig.accounts().getDepositPrincipal(msg.sender, _token);
        return globalConfig.accounts().getDepositPrincipal(msg.sender, _token);
    }

    function getDepositInterest(address _token) public view returns (uint256) {
        /* TokenRegistry.TokenInfo storage tokenInfo = accountVariable.tokenInfos[_token];
        uint256 lastDepositBlock = globalConfig.accounts().getLastDepositBlock(msg.sender, _token);
        uint256 accruedRate = globalConfig.bank().getDepositAccruedRate(_token, lastDepositBlock);
        return tokenInfo.calculateDepositInterest(accruedRate); */
        return globalConfig.accounts().getDepositInterest(msg.sender, _token);

    }

    function getDepositBalance(address _token, address _accountAddr) public view returns (uint256) {
        return globalConfig.accounts().getDepositBalanceCurrent(_token, _accountAddr);
    }

    function getBorrowPrincipal(address _token) public view returns (uint256) {
        //TokenRegistry.TokenInfo storage tokenInfo = globalConfig.accounts().accounts[msg.sender].tokenInfos[_token];
        return globalConfig.accounts().getBorrowPrincipal(msg.sender, _token);
    }

    function getBorrowInterest(address _token) public view returns (uint256) {
        /* TokenRegistry.TokenInfo storage tokenInfo = globalConfig.accounts().accounts[msg.sender].tokenInfos[_token];
        uint256 accruedRate = globalConfig.bank().getBorrowAccruedRate(_token, tokenInfo.getLastBorrowBlock());
        return tokenInfo.calculateBorrowInterest(accruedRate); */
        return globalConfig.accounts().getBorrowInterest(msg.sender, _token);
    }

    function getBorrowBalance(address _token, address _accountAddr) public view returns (uint256) {
        return globalConfig.accounts().getBorrowBalanceCurrent(_token, _accountAddr);
    }

    function getBorrowETH(address _account) public view returns (uint256) {
        return globalConfig.accounts().getBorrowETH(_account);
    }

    function getDepositETH(address _account) public view returns (uint256) {
        return globalConfig.accounts().getDepositETH(_account);
    }

    function getTokenPrice(address _token) public view returns (uint256) {
        return globalConfig.tokenInfoRegistry().priceFromAddress(_token);
    }

    function getTokenState(address _token) public view returns (uint256 deposits, uint256 loans, uint256 reserveBalance, uint256 remainingAssets){
        return globalConfig.bank().getTokenState(_token);
    }
}