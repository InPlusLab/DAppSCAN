// SPDX-License-Identifier: MIT

pragma solidity =0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "../governance/InitializableOwner.sol";
import "../interfaces/IBurnableERC20.sol";
import "../base/BasicMetaTransaction.sol";

contract CashierDesk is InitializableOwner, BasicMetaTransaction {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    event ChargeToken(
        address indexed sender,
        address indexed token,
        uint256 value,
        uint256 timestamp
    );

    event WithdrawToken(
        address indexed sender,
        address indexed token,
        uint256 value,
        uint256 timestamp
    );

    event WithdrawToAddress(
        address indexed sender,
        address indexed token,
        uint256 value,
        uint256 timestamp
    );

    event AddSupportToken(address Token, uint256 timestamp);

    using EnumerableSet for EnumerableSet.AddressSet;
    EnumerableSet.AddressSet private _admin;

    using EnumerableSet for EnumerableSet.AddressSet;
    EnumerableSet.AddressSet private _support_token;

    uint256 public total_charge;
    uint256 public total_burn;

    constructor() public {
        initialize();
    }

    function initialize() public {
        super._initialize();
    }

    modifier onlyCaller() {
        require(_admin.contains(msgSender()) == true, "only caller.");
        _;
    }

    function addSupportToken(address token) public onlyOwner returns (bool) {
        require(token != address(0), "address is zero");
        require(_support_token.contains(token) == false, "ready support.");
        _support_token.add(token);

        emit AddSupportToken(token, block.timestamp);

        return true;
    }

    function addAdmin(address ad) public onlyOwner returns (bool) {
        _admin.add(ad);
    }

    function removeAdmin(address ad) public onlyOwner returns (bool) {
        _admin.remove(ad);
    }

    function listAdmin() public view onlyOwner returns (address[] memory) {
        uint256 len = _admin.length();
        address[] memory ls = new address[](len);

        for (uint256 i = 0; i < len; ++i) {
            ls[i] = _admin.at(i);
        }
        return ls;
    }

    function chargeToken(address token, uint256 amount) public returns (bool) {
        require(_support_token.contains(token) == true, "cant support token.");

        IERC20 erc20 = IERC20(token);

        uint256 oldBal = erc20.balanceOf(address(this));
        erc20.safeTransferFrom(msgSender(), address(this), amount);
        amount = erc20.balanceOf(address(this)).sub(oldBal);

        total_charge += amount;
        emit ChargeToken(msgSender(), token, amount, block.timestamp);

        return true;
    }

    function Withdraw(
        address token,
        address[] memory users,
        uint256[] memory values
    ) public onlyCaller returns (bool) {
        require(_support_token.contains(token) == true, "cant support token.");
        require(users.length == values.length, "bad length");

        IERC20 erc20 = IERC20(token);

        for (uint256 i = 0; i < users.length; i++) {

            erc20.safeTransfer(users[i], values[i]);

            emit WithdrawToken(users[i], token, values[i], block.timestamp);
        }
        return true;
    }
   
    function burnToken(
        address token,
        uint256 total
    ) public onlyCaller returns (bool) {
        require(_support_token.contains(token) == true, "cant support token.");

        IBurnableERC20 erc20 = IBurnableERC20(token);
        
        total_burn += total;
        erc20.burn(total_burn);
        return true;
    }

    function withdrawToAddress(address token, uint256 balance) public onlyCaller returns(bool){
        require(_support_token.contains(token) == true, "cant support token.");
         
        IERC20 erc20 = IERC20(token);
        erc20.safeTransfer(token, balance);

        emit WithdrawToAddress(msgSender(), token, balance, block.timestamp);
        return true;
    }

}
