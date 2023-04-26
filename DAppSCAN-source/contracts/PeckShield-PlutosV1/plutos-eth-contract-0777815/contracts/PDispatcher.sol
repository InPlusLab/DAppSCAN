pragma solidity >=0.4.21 <0.6.0;
import "../utils/Ownable.sol";

contract PDispatcher is Ownable{

  mapping (bytes32 => address ) public targets;

  constructor() public{}

  event TargetChanged(bytes32 key, address old_target, address new_target);
  function resetTarget(bytes32 _key, address _target) public onlyOwner{
    address old = address(targets[_key]);
    targets[_key] = _target;
    emit TargetChanged(_key, old, _target);
  }

  function getTarget(bytes32 _key) public view returns (address){
    return targets[_key];
  }
}

contract PDispatcherFactory{
  event NewPDispatcher(address addr);

  function createHDispatcher() public returns(address){
      PDispatcher dis = new PDispatcher();
      dis.transferOwnership(msg.sender);
      emit NewPDispatcher(address(dis));
      return address(dis);
  }
}
