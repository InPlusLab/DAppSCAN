// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;


import "./interfaces/IStaker.sol";
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';


/*
This is a temporary contract for minimal requirements to deploy cvxFXS before
the staking platform is complete
*/
contract BoosterPlaceholder{
    using SafeERC20 for IERC20;

    address public constant fxs = address(0x3432B6A60D23Ca0dFCa7761B7ab56459D9C964D0);

    address public immutable proxy;
    address public owner;
    address public feeclaimer;
    bool public isShutdown;
    address public feeQueue;

    event DelegateSet(address indexed _address);
    event FeesClaimed(uint256 _amount);
    event Recovered(address indexed _token, uint256 _amount);

    constructor(address _proxy) {
        proxy = _proxy;
        isShutdown = false;
        owner = msg.sender;
        feeclaimer = msg.sender;
    }

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
    
    //shutdown this contract.
    function shutdownSystem() external onlyOwner{
        isShutdown = true;
    }

    //set voting delegate
    function setDelegate(address _delegateContract, address _delegate, bytes32 _space) external onlyOwner{
        bytes memory data = abi.encodeWithSelector(bytes4(keccak256("setDelegate(bytes32,address)")), _space, _delegate);
        IStaker(proxy).execute(_delegateContract,uint256(0),data);
        emit DelegateSet(_delegate);
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

}