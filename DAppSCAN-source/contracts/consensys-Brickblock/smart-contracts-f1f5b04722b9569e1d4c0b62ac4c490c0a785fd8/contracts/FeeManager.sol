pragma solidity 0.4.23;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "./interfaces/IAccessToken.sol";
import "./interfaces/IRegistry.sol";


contract FeeManager {
  using SafeMath for uint256;

  uint8 public constant version = 1;
  uint256 actRate = 1000;

  IRegistry private registry;

  constructor(
    address _registryAddress
  )
    public
  {
    require(_registryAddress != address(0));
    registry = IRegistry(_registryAddress);
  }

  function weiToAct(uint256 _wei)
    view
    public
    returns (uint256)
  {

    return _wei.mul(actRate);
  }

  function actToWei(uint256 _act)
    view
    public
    returns (uint256)
  {
    return _act.div(actRate);
  }

  function payFee()
    public
    payable
    returns (bool)
  {
    IAccessToken act = IAccessToken(
      registry.getContractAddress("AccessToken")
    );
    require(act.distribute(weiToAct(msg.value)));
    return true;
  }

  function claimFee(
    uint256 _value
  )
    public
    returns (bool)
  {
    IAccessToken act = IAccessToken(
      registry.getContractAddress("AccessToken")
    );
    require(act.burn(msg.sender, _value));
    msg.sender.transfer(actToWei(_value));
    return true;
  }

  // prevent anyone from sending funds other than selfdestructs of course :)
  function()
    public
    payable
  {
    revert();
  }

}
