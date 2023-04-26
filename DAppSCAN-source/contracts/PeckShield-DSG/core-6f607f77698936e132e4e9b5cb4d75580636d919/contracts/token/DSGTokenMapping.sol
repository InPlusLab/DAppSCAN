// SPDX-License-Identifier: MIT

pragma solidity =0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "./DelegateERC20.sol";

contract DSGTokenMapping is DelegateERC20, Ownable {

    event AddWhiteList(address user);
    event RemoveWhiteList(address user);

    address public feeWallet;

    uint256 public vTokenFeeRate = 2;
    uint256 public burnRate = 3;

    mapping(address => bool) _whiteList;

    using EnumerableSet for EnumerableSet.AddressSet;
    EnumerableSet.AddressSet private _minters;

    constructor(address _feeWallet) public ERC20("Dinosaur Eggs Token", "DSG") {
        feeWallet = _feeWallet;
    }

    function setFeeWallet(address _feeWallet) public onlyOwner {
        feeWallet = _feeWallet;
    }

    function setVTokenFeeRate(uint256 rate) public onlyOwner {
        require(rate < 100, "bad num");

        vTokenFeeRate = rate;
    }

    function setBurnRate(uint256 rate) public onlyOwner {
        require(rate < 100, "bad num");

        burnRate = rate;
    }

    function addWhiteList(address user) public onlyOwner {
        _whiteList[user] = true;

        emit AddWhiteList(user);
    }

    function removeWhiteList(address user) public onlyOwner {
        delete _whiteList[user];

        emit RemoveWhiteList(user);
    }

    function isWhiteList(address user) public view returns(bool) {
        return _whiteList[user];
    }

    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal virtual override {
        uint256 _amount = amount;
        if(_whiteList[sender] == false && _whiteList[recipient] == false && recipient != address(0)) {
            if(vTokenFeeRate > 0) {
                uint256 fee = _amount.mul(vTokenFeeRate).div(10000);
                amount = amount.sub(fee);
                super._transfer(sender, feeWallet, fee);
            }

            if(burnRate > 0) {
                uint256 burn = _amount.mul(burnRate).div(10000);
                amount = amount.sub(burn);
                _burn(sender, burn);
            }
        }

        super._transfer(sender, recipient, amount);
    }

    function mint(address _to, uint256 _amount) public onlyMinter returns (bool) {

        _mint(_to, _amount);

        return true;
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    function addMinter(address _addMinter) public onlyOwner returns (bool) {
        require(_addMinter != address(0), "Token: _addMinter is the zero address");
        return EnumerableSet.add(_minters, _addMinter);
    }

    function delMinter(address _delMinter) public onlyOwner returns (bool) {
        require(_delMinter != address(0), "Token: _delMinter is the zero address");
        return EnumerableSet.remove(_minters, _delMinter);
    }

    function getMinterLength() public view returns (uint256) {
        return EnumerableSet.length(_minters);
    }

    function isMinter(address account) public view returns (bool) {
        return EnumerableSet.contains(_minters, account);
    }

    function getMinter(uint256 _index) public view onlyOwner returns (address) {
        require(_index <= getMinterLength() - 1, "Token: index out of bounds");
        return EnumerableSet.at(_minters, _index);
    }

    // modifier for mint function
    modifier onlyMinter() {
        require(isMinter(msg.sender), "caller is not the minter");
        _;
    }
}
