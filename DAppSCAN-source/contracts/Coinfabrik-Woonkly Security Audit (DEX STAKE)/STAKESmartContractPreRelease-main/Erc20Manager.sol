// SPDX-License-Identifier: MIT
pragma solidity ^0.6.6;

import "https://github.com/Woonkly/OpenZeppelinBaseContracts/contracts/math/SafeMath.sol";
import "https://github.com/Woonkly/MartinHSolUtils/Utils.sol";
import "https://github.com/Woonkly/OpenZeppelinBaseContracts/contracts/GSN/Context.sol";

/**
MIT License

Copyright (c) 2021 Woonkly OU

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED BY WOONKLY OU "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/

contract Erc20Manager is Context {
    using SafeMath for uint256;

    //Section Type declarations

    struct E20 {
        address sc;
        uint8 flag; //0 no exist  1 exist 2 deleted
    }

    //Section State variables

    uint256 internal _lastIndexE20s;
    mapping(uint256 => E20) internal _E20s;
    mapping(address => uint256) internal _IDE20sIndex;
    uint256 internal _E20Count;

    //Section Modifier

    modifier onlyNewERC20(address sc) {
        require(!this.ERC20Exist(sc), "E2 Exist");
        _;
    }

    modifier onlyERC20Exist(address sc) {
        require(this.ERC20Exist(sc), "E2 !Exist");
        _;
    }

    modifier onlyERC20IndexExist(uint256 index) {
        require(this.ERC20IndexExist(index), "E2I !Exist");
        _;
    }

    //Section Events

    event NewERC20(address sc);
    event ERC20Removed(address sc);

    //Section functions

    constructor() internal {
        _lastIndexE20s = 0;
        _E20Count = 0;
    }

    function hasContracts() external view returns (bool) {
        return (_E20Count > 0);
    }

    function getERC20Count() external view returns (uint256) {
        return _E20Count;
    }

    function getLastIndexERC20s() external view returns (uint256) {
        return _lastIndexE20s;
    }

    function ERC20Exist(address sc) public view returns (bool) {
        return _E20Exist(_IDE20sIndex[sc]);
    }

    function ERC20IndexExist(uint256 index) public view returns (bool) {
        return (index < (_lastIndexE20s + 1));
    }

    function _E20Exist(uint256 E20ID) internal view returns (bool) {
        return (_E20s[E20ID].flag == 1);
    }

    function newERC20(address sc) internal onlyNewERC20(sc) returns (uint256) {
        _lastIndexE20s = _lastIndexE20s.add(1);
        _E20Count = _E20Count.add(1);

        _E20s[_lastIndexE20s].sc = sc;
        _E20s[_lastIndexE20s].flag = 1;

        _IDE20sIndex[sc] = _lastIndexE20s;

        emit NewERC20(sc);
        return _lastIndexE20s;
    }

    function removeERC20(address sc) internal onlyERC20Exist(sc) {
        _E20s[_IDE20sIndex[sc]].flag = 2;
        _E20s[_IDE20sIndex[sc]].sc = address(0);
        _E20Count = _E20Count.sub(1);
        emit ERC20Removed(sc);
    }

    function getERC20ByIndex(uint256 index) external view returns (address) {
        return _E20s[index].sc;
    }

    function getAllERC20()
        external
        view
        returns (uint256[] memory, address[] memory)
    {
        uint256[] memory indexs = new uint256[](_E20Count);
        address[] memory pACCs = new address[](_E20Count);
        uint256 ind = 0;

        for (uint32 i = 0; i < (_lastIndexE20s + 1); i++) {
            E20 memory p = _E20s[i];
            if (p.flag == 1) {
                indexs[ind] = i;
                pACCs[ind] = p.sc;
                ind++;
            }
        }

        return (indexs, pACCs);
    }
}
