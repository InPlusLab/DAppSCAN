pragma solidity >=0.4.21 <0.6.0;
import "../utils/Ownable.sol";
import "./IPDispatcher.sol";
import "./IPriceOracle.sol";
import "./IPMBParams.sol";
import "../assets/TokenBankInterface.sol";
import "../erc20/TokenInterface.sol";
import "./IPLiquidate.sol";
import "../utils/SafeMath.sol";
import "../erc20/SafeERC20.sol";
import "../erc20/ERC20Impl.sol";

contract PMintBurn is Ownable{

  using SafeMath for uint256;
  using SafeERC20 for IERC20;

  struct mbinfo{
    address from;
    uint256 target_token_amount;
    uint256 stable_token_amount;
    bool exist;
  }

  mapping (bytes32 => mbinfo) public deposits;

  IPDispatcher public dispatcher;
  address public target_token;
  address public stable_token;

  address public pool; //this is to hold target_token, and should be TokenBank

  bytes32 public param_key;
  bytes32 public price_key;
  bytes32 public liquidate_key;
  constructor(address _target_token, address _stable_token, address _pool, address _dispatcher) public{
    dispatcher = IPDispatcher(_dispatcher);
    target_token = _target_token;
    stable_token = _stable_token;
    pool = _pool;
    param_key = keccak256(abi.encodePacked(target_token, stable_token, "param"));
    price_key = keccak256(abi.encodePacked(target_token, stable_token, "price"));
    liquidate_key = keccak256(abi.encodePacked(target_token, stable_token, "liquidate"));
  }

  event PDeposit(address addr, bytes32 hash, uint256 amount, uint256 total);
  //SWC-107-Reentrancy: L48-L63
  function deposit(uint256 _amount) public returns(bytes32){
    bytes32 hash = hash_from_address(msg.sender);
    IPMBParams param = IPMBParams(dispatcher.getTarget(param_key));

    require(_amount >= param.minimum_deposit_amount(), "need to be more than minimum amount");

    uint256 prev = IERC20(target_token).balanceOf(pool);
    IERC20(target_token).safeTransferFrom(msg.sender, pool, _amount);
    uint256 amount = IERC20(target_token).balanceOf(pool).safeSub(prev);

    deposits[hash].from = msg.sender;
    deposits[hash].exist = true;
    deposits[hash].target_token_amount = deposits[hash].target_token_amount.safeAdd(amount);
    emit PDeposit(msg.sender, hash, amount, deposits[hash].target_token_amount);
    return hash;
  }

  event PBorrow(address addr, bytes32 hash, uint256 amount);
  function borrow(uint256 _amount) public returns(bytes32){
    bytes32 hash = hash_from_address(msg.sender);
    IPMBParams param = IPMBParams(dispatcher.getTarget(param_key));
    IPriceOracle price = IPriceOracle(dispatcher.getTarget(price_key));
    require(price.getPrice() > 0, "price not set");

    uint256 m = price.getPrice().safeMul(deposits[hash].target_token_amount).safeMul(param.ratio_base()).safeDiv(uint(10)**ERC20Base(target_token).decimals()).safeDiv(param.mortgage_ratio());
    require(_amount <= m.safeSub(deposits[hash].stable_token_amount), "no left quota");

    deposits[hash].stable_token_amount = deposits[hash].stable_token_amount.safeAdd(_amount);

    TokenInterface(stable_token).generateTokens(msg.sender, _amount);

    emit PBorrow(msg.sender, hash, _amount);
    return hash;
  }

  event PRepay(address addr, bytes32 hash, uint256 amount);
  function repay(uint256 _amount) public returns(bytes32){
    require(IERC20(stable_token).balanceOf(msg.sender) >= _amount, "no enough stable coin");
    bytes32 hash = hash_from_address(msg.sender);
    require(_amount <= deposits[hash].stable_token_amount, "repay too much");

    deposits[hash].stable_token_amount = deposits[hash].stable_token_amount.safeSub(_amount);
    TokenInterface(stable_token).destroyTokens(msg.sender, _amount);
    emit PRepay(msg.sender, hash, _amount);
    return hash;
  }

  event PWithdraw(address addr, bytes32 hash, uint256 amount, uint256 fee);
  function withdraw(uint256 _amount) public returns(bytes32){
    bytes32 hash = hash_from_address(msg.sender);

    IPMBParams param = IPMBParams(dispatcher.getTarget(param_key));
    IPriceOracle price = IPriceOracle(dispatcher.getTarget(price_key));

    uint256 m = deposits[hash].stable_token_amount.safeMul(uint256(10)**ERC20Base(target_token).decimals()).safeMul(param.mortgage_ratio()).safeDiv(price.getPrice()).safeDiv(param.ratio_base());

    require(m + _amount <= deposits[hash].target_token_amount, "claim too much");

    deposits[hash].target_token_amount = deposits[hash].target_token_amount.safeSub(_amount);

    if(param.withdraw_fee_ratio() != 0 && param.plut_fee_pool() != address(0x0)){
      uint256 t = _amount.safeMul(param.withdraw_fee_ratio()).safeDiv(param.ratio_base());
      TokenBankInterface(pool).issue(target_token, msg.sender, _amount.safeSub(t));
      TokenBankInterface(pool).issue(target_token, param.plut_fee_pool(), t);
      emit PWithdraw(msg.sender, hash, _amount.safeSub(t), t);
    }else{
      TokenBankInterface(pool).issue(target_token, msg.sender, _amount);
      emit PWithdraw(msg.sender, hash, _amount, 0);
    }

    return hash;
  }

  event PLiquidate(address addr, bytes32 hash, uint256 target_amount, uint256 stable_amount);
  function liquidate(bytes32 _hash, uint256 _target_amount) public returns(bytes32){
    IPMBParams param = IPMBParams(dispatcher.getTarget(param_key));
    IPriceOracle price = IPriceOracle(dispatcher.getTarget(price_key));
    IPLiquidate lq = IPLiquidate(dispatcher.getTarget(liquidate_key));

    bytes32 hash = _hash;
    require(deposits[hash].exist, "hash not exist");
    require(_target_amount <= deposits[hash].target_token_amount, "too much target token");
    uint256 m = price.getPrice().safeMul(deposits[hash].target_token_amount).safeMul(param.ratio_base()).safeDiv(uint(10)**ERC20Base(target_token).decimals()).safeDiv(param.mortgage_ratio());
    require(m < deposits[hash].stable_token_amount, "mortgage ratio is high, cannot liquidate");

    uint256 stable_amount = deposits[hash].stable_token_amount.safeMul(_target_amount).safeDiv(deposits[hash].target_token_amount);

    require(stable_amount > 0, "nothing to liquidate");

    lq.liquidate_asset(msg.sender,_target_amount, stable_amount);

    deposits[hash].target_token_amount = deposits[hash].target_token_amount.safeSub(_target_amount);
    deposits[hash].stable_token_amount = deposits[hash].stable_token_amount.safeSub(stable_amount);

    emit PLiquidate(msg.sender, hash, _target_amount, stable_amount);
    return hash;
  }

  function get_liquidate_stable_amount(bytes32 _hash, uint256 _target_amount) public view returns(uint256){

    bytes32 hash = _hash;
    if(!deposits[hash].exist) {
      return 0;
    }
    require(_target_amount <= deposits[hash].target_token_amount, "too much target token");

    uint256 stable_amount = deposits[hash].stable_token_amount.safeMul(_target_amount).safeDiv(deposits[hash].target_token_amount);
    return stable_amount;
  }

  function is_liquidatable(bytes32 _hash) public view returns(bool){
    bytes32 hash = _hash;
    IPMBParams param = IPMBParams(dispatcher.getTarget(param_key));
    IPriceOracle price = IPriceOracle(dispatcher.getTarget(price_key));
    if(!deposits[hash].exist){
      return false;
    }

    uint256 m = price.getPrice().safeMul(deposits[hash].target_token_amount).safeMul(param.ratio_base()).safeDiv(uint(10)**ERC20Base(target_token).decimals()).safeDiv(param.mortgage_ratio());
    if(m < deposits[hash].stable_token_amount){
      return true;
    }
    return false;
  }

  function hash_from_address(address _addr) public pure returns(bytes32){
    return keccak256(abi.encodePacked("plutos", _addr));
  }
}
