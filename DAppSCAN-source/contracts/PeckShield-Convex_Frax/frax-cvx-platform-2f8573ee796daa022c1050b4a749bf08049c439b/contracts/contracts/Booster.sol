// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;


import "./interfaces/IStaker.sol";
import "./interfaces/IPoolRegistry.sol";
import "./interfaces/IProxyVault.sol";
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';


/*
Main interface for the whitelisted proxy contract.
*/
contract Booster{
    using SafeERC20 for IERC20;

    address public constant fxs = address(0x3432B6A60D23Ca0dFCa7761B7ab56459D9C964D0);

    address public immutable proxy;
    address public immutable poolRegistry;
    address public immutable feeRegistry;
    address public owner;
    address public rewardManager;
    address public feeclaimer;
    bool public isShutdown;
    address public feeQueue;

    event DelegateSet(address indexed _address);
    event FeesClaimed(uint256 _amount);
    event Recovered(address indexed _token, uint256 _amount);

    constructor(address _proxy, address _poolReg, address _feeReg) {
        proxy = _proxy;
        poolRegistry = _poolReg;
        feeRegistry = _feeReg;
        isShutdown = false;
        owner = msg.sender;
        rewardManager = msg.sender;
        feeclaimer = msg.sender;
    }

    /////// Owner Section /////////

    modifier onlyOwner() {
        require(owner == msg.sender, "!auth");
        _;
    }

    //set owner
    function setOwner(address _owner) external onlyOwner{
        owner = _owner;
    }

    //set fee queue, a contract fees are moved to when claiming
    function setFeeQueue(address _queue) external onlyOwner{
        feeQueue = _queue;
    }

    //set who can call claim fees, 0x0 address will allow anyone to call
    function setFeeClaimer(address _claimer) external onlyOwner{
        feeclaimer = _claimer;
    }

    //set a reward manager address that controls extra reward contracts for each pool
    function setRewardManager(address _rmanager) external onlyOwner{
        rewardManager = _rmanager;
    }
    
    //shutdown this contract.
    function shutdownSystem() external onlyOwner{
        //This version of booster does not require any special steps before shutting down
        //and can just immediately be set.
        isShutdown = true;
    }

    //claim operator roles for certain systems for direct access
    function claimOperatorRoles() external onlyOwner{
        require(!isShutdown,"shutdown");

        //claim operator role of pool registry
        bytes memory data = abi.encodeWithSelector(bytes4(keccak256("setOperator(address)")), address(this));
        IStaker(proxy).execute(poolRegistry,uint256(0),data);
    }

    //set fees on user vaults
    function setPoolFees(uint256 _cvxfxs, uint256 _cvx, uint256 _platform) external onlyOwner{
        require(!isShutdown,"shutdown");

        bytes memory data = abi.encodeWithSelector(bytes4(keccak256("setFees(uint256,uint256,uint256)")), _cvxfxs, _cvx, _platform);
        IStaker(proxy).execute(feeRegistry,uint256(0),data);
    }

    //set fee deposit address for all user vaults
    function setPoolFeeDeposit(address _deposit) external onlyOwner{
        require(!isShutdown,"shutdown");

        bytes memory data = abi.encodeWithSelector(bytes4(keccak256("setDepositAddress(address)")), _deposit);
        IStaker(proxy).execute(feeRegistry,uint256(0),data);
    }

    //add pool on registry
    function addPool(address _implementation, address _stakingAddress, address _stakingToken) external onlyOwner{
        IPoolRegistry(poolRegistry).addPool(_implementation, _stakingAddress, _stakingToken);
    }

    //set a new reward pool implementation for future pools
    function setPoolRewardImplementation(address _impl) external onlyOwner{
        IPoolRegistry(poolRegistry).setRewardImplementation(_impl);
    }

    //deactivate a pool
    function deactivatePool(uint256 _pid) external onlyOwner{
        IPoolRegistry(poolRegistry).deactivatePool(_pid);
    }

    //set extra reward contracts to be active when pools are created
    function setRewardActiveOnCreation(bool _active) external onlyOwner{
        IPoolRegistry(poolRegistry).setRewardActiveOnCreation(_active);
    }

    //vote for gauge weights
    function voteGaugeWeight(address _controller, address _gauge, uint256 _weight) external onlyOwner{
        bytes memory data = abi.encodeWithSelector(bytes4(keccak256("vote_for_gauge_weights(address,uint256)")), _gauge, _weight);
        IStaker(proxy).execute(_controller,uint256(0),data);
    }

    //set voting delegate
    function setDelegate(address _delegateContract, address _delegate, bytes32 _space) external onlyOwner{
        bytes memory data = abi.encodeWithSelector(bytes4(keccak256("setDelegate(bytes32,address)")), _space, _delegate);
        IStaker(proxy).execute(_delegateContract,uint256(0),data);
        emit DelegateSet(_delegate);
    }

    //recover tokens on this contract
    function recoverERC20(address _tokenAddress, uint256 _tokenAmount, address _withdrawTo) external onlyOwner{
        IERC20(_tokenAddress).safeTransfer(_withdrawTo, _tokenAmount);
        emit Recovered(_tokenAddress, _tokenAmount);
    }

    //recover tokens on the proxy
    function recoverERC20FromProxy(address _tokenAddress, uint256 _tokenAmount, address _withdrawTo) external onlyOwner{

        bytes memory data = abi.encodeWithSelector(bytes4(keccak256("transfer(address,uint256)")), _withdrawTo, _tokenAmount);
        IStaker(proxy).execute(_tokenAddress,uint256(0),data);

        emit Recovered(_tokenAddress, _tokenAmount);
    }

    //////// End Owner Section ///////////


    function createVault(uint256 _pid) external{
    	//create minimal proxy vault for specified pool
        (address vault, address stakeAddress, address stakeToken, address rewards) = IPoolRegistry(poolRegistry).addUserVault(_pid, msg.sender);

    	//make voterProxy call proxyToggleStaker(vault) on the pool's stakingAddress to set it as a proxied child
        bytes memory data = abi.encodeWithSelector(bytes4(keccak256("proxyToggleStaker(address)")), vault);
        IStaker(proxy).execute(stakeAddress,uint256(0),data);

    	//call proxy initialize
        IProxyVault(vault).initialize(msg.sender, stakeAddress, stakeToken, rewards);
    }


    //claim fees - if set, move to a fee queue that rewards can pull from
    function claimFees(address _distroContract, address _token) external {
        require(feeclaimer == address(0) || feeclaimer == msg.sender, "!auth");

        uint256 bal;
        if(feeQueue != address(0)){
            bal = IStaker(proxy).claimFees(_distroContract, _token, feeQueue);
        }else{
            bal = IStaker(proxy).claimFees(_distroContract, _token, address(this));
        }
        emit FeesClaimed(bal);
    }

    //call vefxs checkpoint
    function checkpointFeeRewards(address _distroContract) external {
        require(feeclaimer == address(0) || feeclaimer == msg.sender, "!auth");

        IStaker(proxy).checkpointFeeRewards(_distroContract);
    }

    

}