pragma solidity >=0.4.21 <0.6.0;
import "../utils/TokenClaimer.sol";
import "../utils/Ownable.sol";
import "../utils/SafeMath.sol";
import "../erc20/IERC20.sol";
import "../erc20/ERC20Impl.sol";
import "../utils/Address.sol";
import "../erc20/SafeERC20.sol";
import "./Interfaces.sol";




contract TradeInterface{
   function get_total_chip() public view returns(uint256);

}

contract Entry is Ownable{
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    address public stable_token;
    address public chip;
    TradeInterface public vtrade;
    uint256 public min_amount;
    constructor(address _stable_token, address _chip, address _vtrade) public{
        stable_token = _stable_token;
        chip = _chip;
        vtrade = TradeInterface(_vtrade);
    }

    event PUSDDeposit(uint256 stable_amount, uint256 chip_amount);
    function deposit(uint256 _amount) public{
        require(_amount >= min_amount, "too small amount");
        uint before = IERC20(stable_token).balanceOf(address(this));
        IERC20(stable_token).safeTransferFrom(msg.sender, address(this), _amount);
        uint _after = IERC20(stable_token).balanceOf(address(this));
        uint amount = _after.safeSub(before);
        uint chip_amount;
        if (before == 0){
            chip_amount = amount;
        }
        else{
            chip_amount = vtrade.get_total_chip().safeMul(amount).safeDiv(before);
        }
        TokenInterface(chip).generateTokens(msg.sender, chip_amount);
        emit PUSDDeposit(amount, chip_amount);
    }
    event PUSDWithdraw(uint256 stable_amount, uint256 chip_amount);
    function withdraw(uint256 _amount) public{
        require(IERC20(chip).balanceOf(msg.sender) >= _amount, "not enough chip");
        uint256 total_chip = TradeInterface(vtrade).get_total_chip();
        uint256 stable_amount = _amount.safeMul(IERC20(stable_token).balanceOf(address(this))).safeDiv(total_chip);
        require(stable_amount <= IERC20(stable_token).balanceOf(address(this)), "error: not enough pusd supply");
        TokenInterface(chip).destroyTokens(msg.sender, _amount);
        IERC20(stable_token).safeTransfer(msg.sender, stable_amount);
        emit PUSDWithdraw(stable_amount, _amount);
    }
    event ChangeMinPUSDAmount(uint256 new_amount);
    function change_min_amount(uint256 _amount) public onlyOwner{
        min_amount = _amount;
        emit ChangeMinPUSDAmount(_amount);
    }
}

contract EntryFactory{
  event CreateEntry(address addr);
  function newEntry(address _stable_token, address _chip, address _vtrade) public returns(address){
    Entry vt = new Entry(_stable_token, _chip, _vtrade);
    emit CreateEntry(address(vt));
    vt.transferOwnership(msg.sender);
    return address(vt);
  }
}
