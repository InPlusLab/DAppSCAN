pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

interface IACL {
    function accessible(address sender, address to, bytes4 sig)
        external
        view
        returns (bool);
}


contract Oracle {
    address public ACL;

    constructor (address _ACL) public {
        ACL = _ACL;
    }

    modifier auth {
        require(IACL(ACL).accessible(msg.sender, address(this), msg.sig), "access unauthorized");
        _;
    }

    function setACL(
        address _ACL) external {
        require(msg.sender == ACL, "require ACL");
        ACL = _ACL;
    }

    struct Price {
        uint price;
        uint  expiration;
    }

    mapping (address => Price) public prices;

    function getExpiration(address token) external view returns (uint) {
        return prices[token].expiration;
    }

    function getPrice(address token) external view returns (uint) {
        return prices[token].price;
    }

    function get(address token) external view returns (uint, bool) {
        return (prices[token].price, valid(token));
    }

    function valid(address token) public view returns (bool) {
        return now < prices[token].expiration;
    }

    // 设置价格为 @val, 保持有效时间为 @exp second.
    function set(address token, uint val, uint exp) external auth {
        prices[token].price = val;
        prices[token].expiration = now + exp;
    }

    //批量设置，减少gas使用
    function batchSet(address[] calldata tokens, uint[] calldata vals, uint[] calldata exps) external auth {
        uint nToken = tokens.length;
        require(nToken == vals.length && vals.length == exps.length, "invalid array length");
        for (uint i = 0; i < nToken; ++i) {
            prices[tokens[i]].price = vals[i];
            prices[tokens[i]].expiration = now + exps[i];
        }
    }
}
