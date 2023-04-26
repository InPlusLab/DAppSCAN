pragma solidity ^0.8.3;
pragma experimental ABIEncoderV2;

interface IRevoTokenContract{
  function balanceOf(address account) external view returns (uint256);
  function totalSupply() external view returns (uint256);
  function transfer(address recipient, uint256 amount) external returns (bool);
  function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
  function allowance(address owner, address spender) external view returns (uint256);
  function approve(address spender, uint256 amount) external returns (bool);
}

interface IRevoLib{
  function getLiquidityValue(uint256 liquidityAmount) external view returns (uint256 tokenRevoAmount, uint256 tokenBnbAmount);
  function getLpTokens(address _wallet) external view returns (uint256);
  function tokenRevoAddress() external view returns (address);
  function calculatePercentage(uint256 _amount, uint256 _percentage, uint256 _precision, uint256 _percentPrecision) external view returns (uint256);
}

interface IRevoNFT{
  function nftsDbIds(string memory _collection, string memory _dbId) external view returns (uint256);
}

library SafeMath {
    function add(uint x, uint y) internal pure returns (uint z) {
        require((z = x + y) >= x, 'ds-math-add-overflow');
    }

    function sub(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x, 'ds-math-sub-underflow');
    }

    function mul(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x, 'ds-math-mul-overflow');
    }
}

contract Context {
    // Empty internal constructor, to prevent people from mistakenly deploying
    // an instance of this contract, which should be used via inheritance.
    constructor () { }

    function _msgSender() public view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes memory) {
        this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
        return msg.data;
    }
}

contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor () {
        address msgSender = _msgSender();
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }

    function owner() public view returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        require(_owner == _msgSender(), "Ownable: caller is not the owner");
        _;
    }
    
    function renounceOwnership() public virtual onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

contract RevoNFTUtils is Ownable {
    using SafeMath for uint256;
     
    address public revoAddress;
    IRevoTokenContract private revoToken;
    address public revoLibAddress;
    IRevoLib private revoLib;
    
    IRevoNFT private revoNFT;
    
    uint256 private nextRevoId;
    uint256 public revoFees;
    
    uint256 public counter;
    
    //PENDING BUY
    ITEMS_SELABLE[99] public itemsSelable;
    mapping(uint256 => PENDING_TX) pendingTx;
    uint256 public firstPending = 1;
    uint256 public lastPending = 0;
    
    struct ITEMS_SELABLE {
        uint256 index;
        string name;
        string description;
        uint256 price;
        string itemType;
        bool enabled;
        uint256 count;
        uint256 maxItems;
        uint8[3] prices;
    }
    
    struct PENDING_TX {
        uint256 itemIndex;
        string dbId;
        string collection;
        uint256 uniqueId;
        string itemType;
        address sender;
    }
    
    event CreateNFT(address sender, string dbId, string collection);
    event BuyItem(address sender, uint256 index);
    
    mapping(address => mapping(string => mapping(string => uint256))) public triggerMintHistory; 

    constructor(address _revoLibAddress, address _revoNFT) public{
        setRevoLib(_revoLibAddress);
        setRevo(revoLib.tokenRevoAddress());
        setRevoNFT(_revoNFT);
        
        revoFees = 10000000000000000000;
        
        uint8[3] memory prices = [1,2,3];
        editItemSelable(0, "REVUP_NAME", "R3VUP description", 1, "image_url", "R3VUP", true, 0, 999999999, prices);
        editItemSelable(1, "EGG_NORMAL_NAME", "Egg normal description", 1, "image_url", "EGG_NORMAL", true, 0, 999999999, prices);
        editItemSelable(2, "EGG_RARE_NAME", "Egg rare description", 1, "image_url", "EGG_RARE", true, 0, 999999999, prices);
        //TODO LEGENDARY ONLY FOR MASTER TIER
        editItemSelable(3, "EGG_LEG_NAME", "Egg legendary description", 1, "image_url", "EGG_LEGENDARY", true, 0, 999999999, prices);
        editItemSelable(4, "BOOSTER_NAME", "Booster description", 1, "image_url", "BOOSTER", true, 0, 999999999, prices);
    }
    
    /*
    Trigger nft creation
    */
    function triggerCreateNFT(string memory _dbId, string memory _collection) public {
        //revoToken.transferFrom(msg.sender, address(this), revoFees);
        
        triggerMintHistory[msg.sender][_collection][_dbId] = revoFees;
        
        enqueuePendingTx(PENDING_TX(0, _dbId, _collection, counter, "", msg.sender));
        
        emit CreateNFT(msg.sender, _dbId, _collection);
        
        counter++;
    }
    
    /*
    Buy item sellable & add pending buy to queue
    */
    function buyItem(uint256 _itemIndex) public {
        require(itemsSelable[_itemIndex].count <= itemsSelable[_itemIndex].maxItems, "All items sold");
        
        enqueuePendingTx(PENDING_TX(_itemIndex, "", "", counter, itemsSelable[_itemIndex].itemType, msg.sender));
        
        revoToken.transferFrom(msg.sender, address(this), getItemPrice(_itemIndex));
        
        itemsSelable[_itemIndex].count = itemsSelable[_itemIndex].count.add(1);
        
        //emit BuyItem(msg.sender, itemsSellable[_itemIndex].index);
        
        counter++;
    }
    
    function getItemPrice(uint256 _itemIndex) public view returns(uint256){
        uint256 price = itemsSelable[_itemIndex].price;
        
        if(!compareStrings(itemsSelable[_itemIndex].itemType, "R3VUP")){
            
            uint256 step = itemsSelable[_itemIndex].maxItems / 3;
            uint priceIndex = itemsSelable[_itemIndex].count <= step ? 0 :
            itemsSelable[_itemIndex].count <= (step * 2) ? 1 : 2;
            
            price = itemsSelable[_itemIndex].prices[priceIndex];
        }
        
        return price;
    }
    
    function setRevoFees(uint256 _fees) public onlyOwner {
        revoFees = _fees;
    }
    
    /*
    Set revo Address & token
    */
    function setRevo(address _revo) public onlyOwner {
        revoAddress = _revo;
        revoToken = IRevoTokenContract(revoAddress);
    }
    
    /*
    Set revoLib Address & libInterface
    */
    function setRevoLib(address _revoLib) public onlyOwner {
        revoLibAddress = _revoLib;
        revoLib = IRevoLib(revoLibAddress);
    }
    
    function setRevoNFT(address _revoNFT) public onlyOwner {
        revoNFT = IRevoNFT(_revoNFT);
    }
    
    function withdrawRevo(uint256 _amount) public onlyOwner {
        revoToken.transfer(owner(), _amount);
    }
    
    function editItemSelable(uint256 _index, string memory _name, string memory _description, uint256 _price, string memory _image, string memory _itemType, bool _enabled,
    uint256 _count, uint256 _maxItems, uint8[3] memory _prices) public onlyOwner{
        itemsSelable[_index].index = _index;
        itemsSelable[_index].name = _name;
        itemsSelable[_index].description = _description;
        itemsSelable[_index].price = _price;
        itemsSelable[_index].itemType = _itemType;
        itemsSelable[_index].enabled = _enabled;
        itemsSelable[_index].count = _count;
        itemsSelable[_index].maxItems = _maxItems;
        itemsSelable[_index].prices = _prices;
    }
    
    function editItemSelablePrices(uint256 _index, uint8[3] memory _prices) public onlyOwner{
        itemsSelable[_index].prices = _prices;
    }
    
    function getAllItemsSelable() public view  returns(ITEMS_SELABLE[] memory){
        uint256 count;
        for(uint i = 0; i < itemsSelable.length; i++){
            if(itemsSelable[i].enabled){
                count++;
            }
        }
        
        ITEMS_SELABLE[] memory itemToReturn = new ITEMS_SELABLE[](count);
        for(uint256 i = 0; i < itemsSelable.length; i++){
            if(itemsSelable[i].enabled){
                itemToReturn[i] = itemsSelable[i];
                itemToReturn[i].price = getItemPrice(i);
            }
        }
        return itemToReturn;
    }
    
    /*
    PENDING BUY QUEUE
    */
    
    function enqueuePendingTx(PENDING_TX memory data) private {
        lastPending += 1;
        pendingTx[lastPending] = data;
    }

    function dequeuePendingTx() public returns (PENDING_TX memory data) {
        require(lastPending >= firstPending);  // non-empty queue

        data = pendingTx[firstPending];

        delete pendingTx[firstPending];
        firstPending += 1;
    }
    
    function countPendingTx() public view returns(uint256){
        return firstPending <= lastPending ? (lastPending - firstPending) + 1 : 0;
    }
    
    function getPendingTx() public view returns(PENDING_TX[] memory items){
        uint256 count = countPendingTx();
        PENDING_TX[] memory itemToReturn = new PENDING_TX[](count);
        
        for(uint256 i = 0; i < count; i ++){
            itemToReturn[i] =  pendingTx[firstPending + i];
        }
        
        return itemToReturn;
    }
    
    function compareStrings(string memory a, string memory b) private pure returns (bool) {
        return (keccak256(abi.encodePacked((a))) == keccak256(abi.encodePacked((b))));
    }
}
