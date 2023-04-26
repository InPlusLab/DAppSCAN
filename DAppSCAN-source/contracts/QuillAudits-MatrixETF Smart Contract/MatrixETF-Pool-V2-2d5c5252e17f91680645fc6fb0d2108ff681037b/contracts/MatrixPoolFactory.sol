// SPDX-License-Identifier: GPL-3.0
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is disstributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

pragma solidity 0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/MatrixPoolFactoryInterface.sol";
import "./interfaces/ProxyFactoryInterface.sol";

contract MatrixPoolFactory is Ownable, MatrixPoolFactoryInterface {
  event LOG_NEW_POOL(address indexed caller, address indexed pool, address indexed implementation);
  event SET_IMPLEMENTATION(address indexed caller, address indexed implementation, address indexed proxyAdmin);

  string public constant signature = "initialize(string,string,address,uint256,uint256)";

  mapping(address => bool) public isMatrixPool;
  ProxyFactoryInterface public proxyFactory;
  address public implementation;
  address public proxyAdmin;

  constructor(
    address _proxyFactory,
    address _implementation,
    address _proxyAdmin
  ) public {
    proxyFactory = ProxyFactoryInterface(_proxyFactory);
    implementation = _implementation;
    proxyAdmin = _proxyAdmin;
  }

  function setProxySettings(address _implementation, address _proxyAdmin) external onlyOwner {
    implementation = _implementation;
    proxyAdmin = _proxyAdmin;
    emit SET_IMPLEMENTATION(msg.sender, _implementation, _proxyAdmin);
  }

  function newPool(
    string calldata _name,
    string calldata _symbol,
    address _controller,
    uint256 _minWeightPerSecond,
    uint256 _maxWeightPerSecond
  ) external override returns (MatrixPoolInterface) {
    address proxy =
      proxyFactory.build(
        implementation,
        proxyAdmin,
        abi.encodeWithSignature(signature, _name, _symbol, _controller, _minWeightPerSecond, _maxWeightPerSecond)
      );
    isMatrixPool[proxy] = true;
    emit LOG_NEW_POOL(msg.sender, proxy, implementation);
    return MatrixPoolInterface(proxy);
  }
}
