pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

interface IACL {
    function accessible(address sender, address to, bytes4 sig)
        external
        view
        returns (bool);
}


/*
 * usr->logic(1,2,3)->route->data(1,2,3)
 */
contract Router {
    address public ACL;

    constructor(address _ACL) public {
        ACL = _ACL;
    }

    modifier auth {
        require(
            IACL(ACL).accessible(msg.sender, address(this), msg.sig),
            "access unauthorized"
        );
        _;
    }

    function setACL(
        address _ACL) external {
        require(msg.sender == ACL, "require ACL");
        ACL = _ACL;
    }

    struct RouterData {
        address defaultDataContract;
        mapping(bytes32 => address) fields;
    }

    uint public bondNr;//total bond count
    mapping(uint => RouterData) public routerDataMap;

    function defaultDataContract(uint id) external view returns (address) {
        return routerDataMap[id].defaultDataContract;
    }
    
    function setDefaultContract(uint id, address _defaultDataContract) external auth {
        routerDataMap[id].defaultDataContract = _defaultDataContract;
    }

    function addField(uint id, bytes32 field, address data) external auth {
        routerDataMap[id].fields[field] = data;
    }

    function setBondNr(uint _bondNr) external auth {
        bondNr = _bondNr;
    }

    //根据field找出合约地址
    function f(uint id, bytes32 field) external view returns (address) {
        if (routerDataMap[id].fields[field] != address(0)) {
            return routerDataMap[id].fields[field];
        }

        return routerDataMap[id].defaultDataContract;
    }
}
