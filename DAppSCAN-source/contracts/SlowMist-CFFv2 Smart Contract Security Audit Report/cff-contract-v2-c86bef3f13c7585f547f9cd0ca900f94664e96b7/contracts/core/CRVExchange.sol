pragma solidity >=0.4.21 <0.6.0;

import "../utils/Ownable.sol";
import "../erc20/IERC20.sol";
import "../utils/AddressArray.sol";
import "../erc20/SafeERC20.sol";


contract SushiUniInterfaceERC20{
  function getAmountsOut(uint256 amountIn, address[] memory path) public view returns(uint256[] memory);
  function swapExactTokensForTokensSupportingFeeOnTransferTokens(uint256 amountIn,   uint256 amountOutMin, address[] calldata path, address to, uint256 deadline) external ;
  function swapExactTokensForETHSupportingFeeOnTransferTokens(uint256 amountIn, uint256 amountOutMin, address[] calldata path, address to, uint256 deadline) external;
}


contract CRVExchangeV2 is Ownable{
  address public crv_token;
  using AddressArray for address[];
  using SafeERC20 for IERC20;

  struct path_info{
    address dex;
    address[] path;
  }
  mapping(bytes32 => path_info) public paths;
  bytes32[] public path_indexes;

  address weth = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

  constructor(address _crv) public{
    if(_crv == address(0x0)){
      crv_token = address(0xD533a949740bb3306d119CC777fa900bA034cd52);
    }else{
      crv_token = _crv;
    }
  }
  function path_from_addr(uint index) public view returns(address){
    return paths[path_indexes[index]].path[0];
  }
  function path_to_addr(uint index) public view returns(address){
    return paths[path_indexes[index]].path[paths[path_indexes[index]].path.length - 1];
  }

  function handleCRV(address target_token, uint256 amount, uint min_amount) public{
    handleExtraToken(crv_token, target_token, amount, min_amount);
  }

  function handleExtraToken(address from, address target_token, uint256 amount, uint min_amount) public{
    uint256 maxOut = 0;
    uint256 fpi = 0;

    for(uint pi = 0; pi < path_indexes.length; pi ++){
      if(path_from_addr(pi) != from || path_to_addr(pi) != target_token){
        continue;
      }
      uint256 t = get_out_for_dex_path(pi, amount);
      if( t > maxOut ){
        fpi = pi;
        maxOut = t;
      }
    }

    address dex = paths[path_indexes[fpi]].dex;
    IERC20(from).safeTransferFrom(msg.sender, address(this), amount);
    IERC20(from).safeApprove(dex, amount);
    if(target_token == weth){
      SushiUniInterfaceERC20(dex).swapExactTokensForETHSupportingFeeOnTransferTokens(amount, min_amount, paths[path_indexes[fpi]].path, address(this), block.timestamp + 10800);
      uint256 target_amount = address(this).balance;
      require(target_amount >= min_amount, "slippage screwed you");
      (bool status, ) = msg.sender.call.value(target_amount)("");
      require(status, "CRVExchange transfer eth failed");
    }else{
      SushiUniInterfaceERC20(dex).swapExactTokensForTokensSupportingFeeOnTransferTokens(amount, min_amount, paths[path_indexes[fpi]].path, address(this), block.timestamp + 10800);
      uint256 target_amount = IERC20(target_token).balanceOf(address(this));
      require(target_amount >= min_amount, "slippage screwed you");
      IERC20(target_token).safeTransfer(address(msg.sender), target_amount);
    }
  }

  function get_out_for_dex_path(uint pi, uint256 _amountIn) internal view returns(uint256) {
    address dex = paths[path_indexes[pi]].dex;
    uint256[] memory ret = SushiUniInterfaceERC20(dex).getAmountsOut(_amountIn, paths[path_indexes[pi]].path);
    return ret[ret.length - 1];
  }

  event AddPath(bytes32 hash, address dex, address[] path);
  function addPath(address dex, address[] memory path) public onlyOwner{
    SushiUniInterfaceERC20(dex).getAmountsOut(1e18, path); //This is a double check
    bytes32 hash = keccak256(abi.encodePacked(dex, path));
    require(paths[hash].path.length == 0, "already exist path");
    path_indexes.push(hash);
    paths[hash].path = path;
    paths[hash].dex = dex;
    emit AddPath(hash, dex, path);
  }

  event RemovePath(bytes32 hash);
  function removePath(address dex, address[] memory path) public onlyOwner{
    bytes32 hash = keccak256(abi.encodePacked(dex, path));
    removePathWithHash(hash);
  }

  function removePathWithHash(bytes32 hash) public onlyOwner{
    require(paths[hash].path.length != 0, "path not exist");
    delete paths[hash];
    for(uint i = 0; i < path_indexes.length; i++){
      if(path_indexes[i] == hash){
          path_indexes[i] = path_indexes[path_indexes.length - 1];
          delete path_indexes[path_indexes.length - 1];
          path_indexes.length --;
          emit RemovePath(hash);
          break;
      }
    }
  }

  function() external payable{}
}
