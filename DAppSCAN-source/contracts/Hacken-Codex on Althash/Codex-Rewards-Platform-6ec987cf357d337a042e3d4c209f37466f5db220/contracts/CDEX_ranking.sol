pragma solidity 0.4.21;

import "./BokkyPooBahsRedBlackTreeLibrary.sol";

contract CDEXRanking {
    using BokkyPooBahsRedBlackTreeLibrary for BokkyPooBahsRedBlackTreeLibrary.Tree;

    BokkyPooBahsRedBlackTreeLibrary.Tree tree;
    mapping(uint => address[]) public values;
    mapping(address => uint) public addressPosition;
    address public codexStakingContract;
    address public owner;


    event Log(string where, uint key, address value);

    function CDEXRanking() public {
        owner = msg.sender;
    }
    
    function setCodexContractAddress(address _contractAddress) external {
        require(msg.sender == owner);
        codexStakingContract = _contractAddress;
    }
    
    function getValuesLength(uint _value) public view returns (uint length) {
        length = values[_value].length;
    }
    
    function root() public view returns (uint _key) {
        _key = tree.root;
    }
    
    function first() public view returns (uint _key) {
        _key = tree.first();
    }
    
    function last() public view returns (uint _key) {
        _key = tree.last();
    }
    
    function next(uint key) public view returns (uint _key) {
        _key = tree.next(key);
    }
    
    function prev(uint key) public view returns (uint _key) {
        _key = tree.prev(key);
    }
    
    function exists(uint key) public view returns (bool _exists) {
        _exists = tree.exists(key);
    }
    
    function getNode(uint _key) public view returns (uint key, uint parent, uint left, uint right, bool red) {
        if (tree.exists(_key)) {
            (key, parent, left, right, red) = tree.getNode(_key);
        }
    }
    
    function getValue(uint _key, uint _pos) public view returns (address value) {
        if (tree.exists(_key) && values[_key].length - 1 >= _pos) {
            value = values[_key][_pos];
        }
    }

    function insert(uint _key, address _value) public {
        require(msg.sender == codexStakingContract || msg.sender == owner);
        if (!tree.exists(_key)) {
            tree.insert(_key);
        }
        values[_key].push(_value);
        addressPosition[_value] = values[_key].length - 1;
        emit Log("insert", _key, _value);
    }
    
    function remove(uint _key, address _value) public {
        require(msg.sender == codexStakingContract || msg.sender == owner);
        require(values[_key][addressPosition[_value]] == _value);
        if (values[_key].length == 1) {
            tree.remove(_key);
        } else {
            if (addressPosition[_value] != values[_key].length - 1) {
                address movingValue = values[_key][values[_key].length - 1];
                // Copying the last address in the array to the position of the address to be removed
                values[_key][addressPosition[_value]] = movingValue;
                // Updating the position reference for the moved value
                addressPosition[movingValue] = addressPosition[_value];
            }
        }
        emit Log("remove", _key, values[_key][addressPosition[_value]]);
        // Deleting the last position of the array
        values[_key].length--;
        addressPosition[_value] = 0;
    }
    
    function ranking(uint _positions) public view returns (address[] memory, uint256[] memory) {
        address[] memory _addresses = new address[](_positions);
        uint256[] memory _balances = new uint256[](_positions);
        uint aux = last();
        uint i;
        uint j;
        while (i < _positions) {
            j = 0;
            while (j < values[aux].length && i < _positions) {
                _addresses[i] = values[aux][j];
                _balances[i] = aux;
                i++;
                j++;
            }
            aux = prev(aux);
        }
        return (_addresses, _balances);
    }
}