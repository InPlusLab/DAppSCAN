// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./interfaces/IProxyVault.sol";
import "./interfaces/IFeeRegistry.sol";
import "./interfaces/IFraxFarmUniV3.sol";
import "./interfaces/IRewards.sol";
import "./interfaces/INonfungiblePositionManager.sol";
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';


contract StakingProxyUniV3 is IProxyVault{
    using SafeERC20 for IERC20;

    address public constant fxs = address(0x3432B6A60D23Ca0dFCa7761B7ab56459D9C964D0);
    address public constant vefxsProxy = address(0x59CFCD384746ec3035299D90782Be065e466800B);
    address public constant positionManager = address(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);
    address public immutable feeRegistry; //fee registry

    address public owner; //owner of the vault
    address public stakingAddress; //farming contract
    address public rewards; //extra rewards on convex

    uint256 public constant FEE_DENOMINATOR = 10000;

    constructor(address _feeRegistry) {
        feeRegistry = _feeRegistry;
    }

    function vaultType() external pure returns(VaultType){
        return VaultType.UniV3;
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
        rewards = _rewardsAddress;

        //set proxy address on staking contract
        IFraxFarmUniV3(_stakingAddress).stakerSetVeFXSProxy(vefxsProxy);

        //set infinite approval
        INonfungiblePositionManager(positionManager).setApprovalForAll(_stakingAddress, true);
    }

    modifier onlyOwner() {
        require(owner == msg.sender, "!auth");
        _;
    }

    // Needed to indicate that this contract is ERC721 compatible
    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

    //create a new locked state of _secs timelength
    function stakeLocked(uint256 _token_id, uint256 _secs) external onlyOwner{
        //take note of amount liquidity staked
        uint256 userLiq = IFraxFarmUniV3(stakingAddress).lockedLiquidityOf(address(this));

        if(_token_id > 0){
            //pull token from user
            INonfungiblePositionManager(positionManager).safeTransferFrom(msg.sender, address(this), _token_id);

            //stake
            IFraxFarmUniV3(stakingAddress).stakeLocked(_token_id, _secs);
        }

        //if rewards are active, checkpoint (can call with _token_id as 0 if rewards were turned on
        // after initial deposit and just need to checkpoint)
        if(IRewards(rewards).active()){
            //get difference of liquidity after deposit
            userLiq = IFraxFarmUniV3(stakingAddress).lockedLiquidityOf(address(this)) - userLiq;
            IRewards(rewards).deposit(owner,userLiq);
        }
    }

    //add to a current lock
    //SWC-107-Reentrancy: L94-L113
    function lockAdditional(uint256 _token_id, uint256 _token0_amt, uint256 _token1_amt) external onlyOwner{
        uint256 userLiq = IFraxFarmUniV3(stakingAddress).lockedLiquidityOf(address(this));

        if(_token_id > 0 && _token0_amt > 0 && _token1_amt > 0){
            address token0 = IFraxFarmUniV3(stakingAddress).uni_token0();
            address token1 = IFraxFarmUniV3(stakingAddress).uni_token1();
            //pull tokens directly to staking address
            IERC20(token0).safeTransferFrom(msg.sender, stakingAddress, _token0_amt);
            IERC20(token1).safeTransferFrom(msg.sender, stakingAddress, _token1_amt);

            //add stake - use balance of override,  min in is ignored when doing so
            IFraxFarmUniV3(stakingAddress).lockAdditional(_token_id, _token0_amt, _token1_amt, 0, 0, true);
        }
        
        //if rewards are active, checkpoint
        if(IRewards(rewards).active()){
            userLiq = IFraxFarmUniV3(stakingAddress).lockedLiquidityOf(address(this)) - userLiq;
            IRewards(rewards).deposit(owner,userLiq);
        }
    }

    //withdraw a staked position
    function withdrawLocked(uint256 _token_id) external onlyOwner{
        //take note of amount liquidity staked
        uint256 userLiq = IFraxFarmUniV3(stakingAddress).lockedLiquidityOf(address(this));

        //withdraw directly to owner(msg.sender)
        IFraxFarmUniV3(stakingAddress).withdrawLocked(_token_id, msg.sender);

        //if rewards are active, checkpoint
        if(IRewards(rewards).active()){
            //get difference of liquidity after withdrawn
            userLiq -= IFraxFarmUniV3(stakingAddress).lockedLiquidityOf(address(this));
            IRewards(rewards).withdraw(owner,userLiq);
        }
    }

    //helper function to combine earned tokens on staking contract and any tokens that are on this vault
    function earned() external view returns (address[] memory token_addresses, uint256[] memory total_earned) {
        //get list of reward tokens
        address[] memory rewardTokens = IFraxFarmUniV3(stakingAddress).getAllRewardTokens();
        uint256[] memory stakedearned = IFraxFarmUniV3(stakingAddress).earned(address(this));
        
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
            // use bool as false at first to claim all farm rewards and process here
            // then call again to claim LP fees but send directly to owner
            IFraxFarmUniV3(stakingAddress).getReward(address(this), false);
            IFraxFarmUniV3(stakingAddress).getReward(owner, true);
        }

        //process fxs fees
        _processFxs();

        //get list of reward tokens
        address[] memory rewardTokens = IFraxFarmUniV3(stakingAddress).getAllRewardTokens();

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
            // use bool as false at first to claim all farm rewards and process here
            // then call again to claim LP fees but send directly to owner
            IFraxFarmUniV3(stakingAddress).getReward(address(this), false);
            IFraxFarmUniV3(stakingAddress).getReward(owner, true);
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
                uint256 userLiq = IFraxFarmUniV3(stakingAddress).lockedLiquidityOf(address(this));
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

    //there should never be an erc721 on this address but since it is a receiver, allow owner to extract any
    //that may exist
    function recoverERC721(address _tokenAddress, uint256 _token_id) external onlyOwner {
        INonfungiblePositionManager(_tokenAddress).safeTransferFrom(address(this), owner, _token_id);
    }
}
