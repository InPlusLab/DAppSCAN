pragma solidity >=0.4.21 <0.6.0;
import "../utils/Ownable.sol";
import "./IPDispatcher.sol";
import "./IPLiquidate.sol";
import "./IPMBParams.sol";
import "../assets/TokenBankInterface.sol";
import "../erc20/TokenInterface.sol";
import "../utils/SafeMath.sol";
import "../erc20/IERC20.sol";

//SWC-135-Code With No Effects: L11-L12
contract PLiquidateAgent is Ownable{

  using SafeMath for uint256;
  address public target_token;
  address public target_token_pool;
  address public stable_token;
  address public target_fee_pool;

  IPDispatcher public dispatcher;
  address public caller;

  bytes32 public param_key;
  constructor(address _target_token, address _target_token_pool, address _stable_token, address _dispatcher) public{
    target_token = _target_token;
    target_token_pool = _target_token_pool;
    stable_token = _stable_token;
    dispatcher = IPDispatcher(_dispatcher);
    param_key = keccak256(abi.encodePacked(target_token, stable_token, "param"));
  }

  modifier onlyCaller{
    require(msg.sender == caller, "not caller");
    _;
  }

  function liquidate_asset(address payable _sender, uint256 _target_amount, uint256 _stable_amount) public onlyCaller{
    IPMBParams param = IPMBParams(dispatcher.getTarget(param_key));

    require(IERC20(stable_token).balanceOf(_sender) >= _stable_amount, "insufficient stable token");
    TokenInterface(stable_token).destroyTokens(_sender, _stable_amount);
    if(param.liquidate_fee_ratio() != 0 && param.plut_fee_pool() != address(0x0)){
      uint256 t = param.liquidate_fee_ratio().safeMul(_target_amount).safeDiv(param.ratio_base());
      TokenBankInterface(target_token_pool).issue(target_token, param.plut_fee_pool(), t);
      TokenBankInterface(target_token_pool).issue(target_token, _sender, _target_amount.safeSub(t));
    }else{
      TokenBankInterface(target_token_pool).issue(target_token, _sender, _target_amount);
    }
  }

  function changeCaller(address _caller) public onlyOwner{
    caller = _caller;
  }

}
