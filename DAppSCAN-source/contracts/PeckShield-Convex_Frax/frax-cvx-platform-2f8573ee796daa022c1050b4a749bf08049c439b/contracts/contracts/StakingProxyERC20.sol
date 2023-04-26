// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./interfaces/IProxyVault.sol";
import "./interfaces/IFeeRegistry.sol";
import "./interfaces/IFraxFarmERC20.sol";
import "./interfaces/IRewards.sol";
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';


contract StakingProxyERC20 is IProxyVault{
    using SafeERC20 for IERC20;

    address public constant fxs = address(0x3432B6A60D23Ca0dFCa7761B7ab56459D9C964D0);
    address public constant vefxsProxy = address(0x59CFCD384746ec3035299D90782Be065e466800B);
    address public immutable feeRegistry; //fee registry

    address public owner; //owner of the vault
    address public stakingAddress; //farming contract
    address public stakingToken; //farming token
    address public rewards; //extra rewards on convex

    uint256 public constant FEE_DENOMINATOR = 10000;

    constructor(address _feeRegistry) {
        feeRegistry = _feeRegistry;
    }

    function vaultType() external pure returns(VaultType){
        return VaultType.Erc20Baic;
    }

    function vaultVersion() external pure returns(uint256){
        return 1;
    }

    //initialize vault
    function initialize(address _owner, address _stakingAddress, address _stakingToken, address _rewardsAddress) external{
        require(owner == address(0),"already init");

        //set variables
        owner = _owner;
        stakingAddress = _stakingAddress;
        stakingToken = _stakingToken;
        rewards = _rewardsAddress;

        //set proxy address on staking contract
        IFraxFarmERC20(_stakingAddress).stakerSetVeFXSProxy(vefxsProxy);

        //set infinite approval
        IERC20(stakingToken).approve(_stakingAddress, type(uint256).max);
    }

    modifier onlyOwner() {
        require(owner == msg.sender, "!auth");
        _;
    }

    //create a new locked state of _secs timelength
    function stakeLocked(uint256 _liquidity, uint256 _secs) external onlyOwner{
        if(_liquidity > 0){
            //pull tokens from user
            IERC20(stakingToken).safeTransferFrom(msg.sender, address(this), _liquidity);

            //stake
            IFraxFarmERC20(stakingAddress).stakeLocked(_liquidity, _secs);
        }
        //if rewards are active, checkpoint (can call with _liquidity as 0 if rewards were turned on
        // after initial deposit and just need to checkpoint)
        if(IRewards(rewards).active()){
            IRewards(rewards).deposit(owner,_liquidity);
        }
    }

    //add to a current lock
    function lockAdditional(bytes32 _kek_id, uint256 _addl_liq) external onlyOwner{
        if(_addl_liq > 0){
            //pull tokens from user
            IERC20(stakingToken).safeTransferFrom(msg.sender, address(this), _addl_liq);

            //add stake
            IFraxFarmERC20(stakingAddress).lockAdditional(_kek_id, _addl_liq);
        }
        //if rewards are active, checkpoint
        if(IRewards(rewards).active()){
            IRewards(rewards).deposit(owner,_addl_liq);
        }
    }

    //withdraw a staked position
    function withdrawLocked(bytes32 _kek_id) external onlyOwner{
        //take note of amount liquidity staked
        uint256 userLiq = IFraxFarmERC20(stakingAddress).lockedLiquidityOf(address(this));

        //withdraw directly to owner(msg.sender)
        IFraxFarmERC20(stakingAddress).withdrawLocked(_kek_id, msg.sender);

        //if rewards are active, checkpoint
        if(IRewards(rewards).active()){
            //get difference of liquidity after withdrawn
            userLiq -= IFraxFarmERC20(stakingAddress).lockedLiquidityOf(address(this));
            IRewards(rewards).withdraw(owner,userLiq);
        }
    }

    //helper function to combine earned tokens on staking contract and any tokens that are on this vault
    function earned() external view returns (address[] memory token_addresses, uint256[] memory total_earned) {
        //get list of reward tokens
        address[] memory rewardTokens = IFraxFarmERC20(stakingAddress).getAllRewardTokens();
        uint256[] memory stakedearned = IFraxFarmERC20(stakingAddress).earned(address(this));
        
        token_addresses = new address[](rewardTokens.length + IRewards(rewards).rewardTokenLength());
        total_earned = new uint256[](rewardTokens.length + IRewards(rewards).rewardTokenLength());
        //add any tokens that happen to be already claimed but sitting on the vault
        //(ex. withdraw claiming rewards)
        for(uint256 i = 0; i < rewardTokens.length; i++){
            token_addresses[i] = rewardTokens[i];
            total_earned[i] = stakedearned[i] + IERC20(rewardTokens[i]).balanceOf(address(this));
        }

        IRewards.EarnedData[] memory extraRewards = IRewards(rewards).claimableRewards(address(this));
        for(uint256 i = 0; i < extraRewards.length; i++){
            token_addresses[i+rewardTokens.length] = extraRewards[i].token;
            total_earned[i+rewardTokens.length] = extraRewards[i].amount;
        }
    }

    /*
    claim flow:
        claim rewards directly to the vault
        calculate fees to send to fee deposit
        send fxs to booster for fees
        get reward list of tokens that were received
        send all remaining tokens to owner

    A slightly less gas intensive approach could be to send rewards directly to booster and have it sort everything out.
    However that makes the logic a bit more complex as well as runs a few future proofing risks
    */
    function getReward() external onlyOwner{
        getReward(true);
    }

    //get reward with claim option.
    //_claim bool is for the off chance that rewardCollectionPause is true so getReward() fails but
    //there are tokens on this vault for cases such as withdraw() also calling claim.
    //can also be used to rescue tokens on the vault
    function getReward(bool _claim) public onlyOwner{

        //claim
        if(_claim){
            IFraxFarmERC20(stakingAddress).getReward(address(this));
        }

        //process fxs fees
        _processFxs();

        //get list of reward tokens
        address[] memory rewardTokens = IFraxFarmERC20(stakingAddress).getAllRewardTokens();

        //transfer
        _transferTokens(rewardTokens);

        //extra rewards
        _processExtraRewards();
    }

    //auxiliary function to supply token list(save a bit of gas + dont have to claim everything)
    //_claim bool is for the off chance that rewardCollectionPause is true so getReward() fails but
    //there are tokens on this vault for cases such as withdraw() also calling claim.
    //can also be used to rescue tokens on the vault
    function getReward(bool _claim, address[] calldata _rewardTokenList) external onlyOwner{

        //claim
        if(_claim){
            IFraxFarmERC20(stakingAddress).getReward(address(this));
        }

        //process fxs fees
        _processFxs();

        //transfer
        _transferTokens(_rewardTokenList);

        //extra rewards
        _processExtraRewards();
    }

    //get extra rewards
    function _processExtraRewards() internal{
        if(IRewards(rewards).active()){
            //check if there is a balance because the reward contract could have be activated later
            uint256 bal = IRewards(rewards).balanceOf(address(this));
            if(bal == 0){
                //bal == 0 and liq > 0 can only happen if rewards were turned on after staking
                uint256 userLiq = IFraxFarmERC20(stakingAddress).lockedLiquidityOf(address(this));
                IRewards(rewards).deposit(owner,userLiq);
            }
            IRewards(rewards).getReward(owner);
        }
    }

    //apply fees to fxs and send remaining to owner
    function _processFxs() internal{

        //get fee rate from booster
        uint256 totalFees = IFeeRegistry(feeRegistry).totalFees();

        //send fxs fees to fee deposit
        uint256 fxsBalance = IERC20(fxs).balanceOf(address(this));
        uint256 sendAmount = fxsBalance * totalFees / FEE_DENOMINATOR;
        if(sendAmount > 0){
            IERC20(fxs).transfer(IFeeRegistry(feeRegistry).feeDeposit(), sendAmount);
        }

        //transfer remaining fxs to owner
        sendAmount = IERC20(fxs).balanceOf(address(this));
        if(sendAmount > 0){
            IERC20(fxs).transfer(msg.sender, sendAmount);
        }
    }

    //transfer other reward tokens besides fxs(which needs to have fees applied)
    function _transferTokens(address[] memory _tokens) internal{
        //transfer all tokens
        for(uint256 i = 0; i < _tokens.length; i++){
            if(_tokens[i] != fxs){
                uint256 bal = IERC20(_tokens[i]).balanceOf(address(this));
                if(bal > 0){
                    IERC20(_tokens[i]).transfer(msg.sender, bal);
                }
            }
        }
    }
}
