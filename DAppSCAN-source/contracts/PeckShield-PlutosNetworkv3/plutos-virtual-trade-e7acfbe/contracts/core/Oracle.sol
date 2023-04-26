pragma solidity >=0.4.21 <0.6.0;
import "../utils/TokenClaimer.sol";
import "../utils/Ownable.sol";
import "../utils/SafeMath.sol";
import "../erc20/IERC20.sol";
import "../erc20/ERC20Impl.sol";
import "../utils/Address.sol";
import "../erc20/SafeERC20.sol";
import "./Interfaces.sol";

contract Oracle is Ownable{
    struct asset_info{
        address oracle_type;
        bytes data;
    }
    mapping (string => asset_info) all_assets;

    constructor() public{
    
    }

    function get_asset_price(string memory name) public returns (uint256){
        address addr = all_assets[name].oracle_type;
        require(addr != address(0), "Invalid Asset");

        bytes memory data = all_assets[name].data;

        (bool succ, bytes memory returndata) = address(addr).call(data);
        require(succ, "Oracle call failed");
        return abi.decode(returndata, (uint256));
    }

    function add_asset(string memory _name, address type_addr, bytes memory _call_data) public onlyOwner{
        all_assets[_name].oracle_type = type_addr;
        all_assets[_name].data = _call_data;
    }
}

contract OracleFactory {
  event CreateOracle(address addr);

  function newOracle() public returns(address){
    Oracle vt = new Oracle();
    emit CreateOracle(address(vt));
    vt.transferOwnership(msg.sender);
    return address(vt);
  }
}