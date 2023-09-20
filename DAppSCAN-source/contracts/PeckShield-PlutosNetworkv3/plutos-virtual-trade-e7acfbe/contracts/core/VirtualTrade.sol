pragma solidity >=0.4.21 <0.6.0;
import "../utils/TokenClaimer.sol";
import "../utils/Ownable.sol";
import "../utils/SafeMath.sol";
import "../erc20/IERC20.sol";
import "../erc20/ERC20Impl.sol";
import "../utils/Address.sol";
import "../erc20/SafeERC20.sol";
import "./Interfaces.sol";


contract OracleInterface{
   function get_asset_price(string memory _name) public view returns(uint256);
   function add_asset(string memory _name, address type_addr, bytes memory call_data) public;
}

contract VirtualTrade is Ownable{
    using SafeMath for uint256;

    struct asset_info{
        mapping (address => uint256) position;
        mapping (address => uint256) invest;
        uint256 total_position;
        bool exist;
    }
    OracleInterface public oracle;
    address public chip;
    mapping (string => asset_info) public all_assets;
    mapping (address => mapping (address => bool)) allowed;
    string[] public all_names;
    uint256 public min_price;
    constructor (address _chip, address _oracle) public{
        chip = _chip;
        oracle = OracleInterface(_oracle);
    }

    event SetAllowed(address owner, address proxy, bool state);
    function set_allow(address _proxy, bool _state) public{
        allowed[msg.sender][_proxy] = _state;
        emit SetAllowed(msg.sender, _proxy, _state);
    }

    event AssetBuyIn(string name, address addr, uint256 chip_amount, uint256 position_amount);
    function buyin(string memory name, uint256 amount, uint256 min_rec, address owner) public returns(uint256){
        require(IERC20(chip).balanceOf(owner) >= amount, "not enough chip");
        require(owner == msg.sender || allowed[owner][msg.sender], "permission denied");
        asset_info storage asset = all_assets[name];
        require(asset.exist, "invalid asset");
        uint256 price = oracle.get_asset_price(name);
        require(price > min_price, "price too low");
        uint256 rec_amount = amount.safeMul(1e18).safeDiv(price);
        require (rec_amount >= min_rec, "Buy sllipage");
        TokenInterface(chip).destroyTokens(owner, amount);
        asset.position[owner] = asset.position[owner].safeAdd(rec_amount);
        asset.invest[owner] = asset.invest[owner].safeAdd(amount);
        asset.total_position = asset.total_position.safeAdd(rec_amount);
        emit AssetBuyIn(name, owner, amount, rec_amount);
        return rec_amount;
    }

    event AssetSell(string name, address addr, uint256 chip_amount, uint256 position_amount);
    function sell(string memory name, uint256 amount, uint256 min_rec, address owner) public returns(uint256){
        asset_info storage asset = all_assets[name];
        require(asset.exist, "invalid asset");
        require(owner == msg.sender || allowed[owner][msg.sender], "permission denied");
        require(asset.position[owner] >= amount, "not enough position");
        uint256 chip_amount = asset.position[owner].safeMul(oracle.get_asset_price(name)).safeDiv(1e18);
        require(chip_amount >= min_rec, "Sell sllipage");
        uint256 before = asset.position[owner];
        asset.position[owner] = before.safeSub(amount);
        asset.total_position = asset.total_position.safeSub(amount);
        asset.invest[owner] = asset.invest[owner].safeMul(asset.position[owner]).safeDiv(before);
        TokenInterface(chip).generateTokens(owner, chip_amount);
        emit AssetSell(name, owner, chip_amount, amount);
        return chip_amount;
    }
    event AssetTransfer(string name, address from, address to, uint256 amount);
    function trasnfer_asset(string memory name, address _to, uint256 amount) public{
        asset_info storage asset = all_assets[name];
        require(asset.exist, "invalid asset");
        require(asset.position[msg.sender] >= amount, "not enough position");
        asset.position[msg.sender] = asset.position[msg.sender].safeSub(amount);
        asset.position[_to] = asset.position[_to].safeAdd(amount);
        emit AssetTransfer(name, msg.sender, _to, amount);
    }

    function index_of(string memory str) public view returns(uint){
        for (uint i = 0; i< all_names.length;i++){
            if (keccak256(abi.encodePacked(all_names[i])) == keccak256(abi.encodePacked(str))){
                return i;
            }
        }
        require(false, "name not found");
    }
    event RemoveAsset(string name);
    function remove_asset(string memory name) public onlyOwner{
        uint index = index_of(name);
        all_names[index] = all_names[all_names.length - 1];

        delete all_names[all_names.length-1];
        all_names.length--;
        all_assets[name].exist = false;
        emit RemoveAsset(name);
    }
    event NewAsset(string name, address type_addr, bytes call_data);
    //SWC-135-Code With No Effects: L107-L112
    function add_asset(string memory name, address type_addr, bytes memory call_data) public onlyOwner{
        all_names.push(name);
        all_assets[name].exist = true;
        oracle.add_asset(name, type_addr, call_data);
        emit NewAsset(name, type_addr, call_data);
    }

    event NewMinPrice(uint256 min_price);
    function set_min_price(uint256 _min_price) public onlyOwner{
        min_price = _min_price;
        emit NewMinPrice(min_price);
    }

    function get_total_chip() public view returns(uint256){
        uint amount = 0;
        for (uint i = 0; i < all_names.length; i++){
            amount = amount.safeAdd(all_assets[all_names[i]].total_position.safeMul(oracle.get_asset_price(all_names[i])).safeDiv(1e18));
        }
        amount = amount.safeAdd(IERC20(chip).totalSupply());
        return amount;
    }
    function get_user_chip(address addr) public view returns(uint256){
        uint amount = 0;
        for (uint i = 0; i < all_names.length; i++){
            amount = amount.safeAdd(all_assets[all_names[i]].position[addr].safeMul(oracle.get_asset_price(all_names[i])).safeDiv(1e18));
        }
        return amount;
    }
}

contract VirtualTradeFactory {
  event CreateVirtualTrade(address addr);

  function newVirtualTrade(address _chip, address _oracle) public returns(address){
    VirtualTrade vt = new VirtualTrade(_chip, _oracle);
    emit CreateVirtualTrade(address(vt));
    vt.transferOwnership(msg.sender);
    return address(vt);
  }
}