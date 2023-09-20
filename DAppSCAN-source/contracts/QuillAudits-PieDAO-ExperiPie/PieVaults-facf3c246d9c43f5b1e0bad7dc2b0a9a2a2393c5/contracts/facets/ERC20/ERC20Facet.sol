// SPDX-License-Identifier: MIT
pragma solidity ^0.7.1;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "diamond-2/contracts/libraries/LibDiamond.sol";

import "../../interfaces/IERC20Facet.sol";
import "./LibERC20Storage.sol";
import "./LibERC20.sol";
import "../shared/Access/CallProtection.sol";

contract ERC20Facet is IERC20, IERC20Facet, CallProtection {
  using SafeMath for uint256;

  function initialize(
    uint256 _initialSupply,
    string memory _name,
    string memory _symbol
  ) external override {
    LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
    LibERC20Storage.ERC20Storage storage es = LibERC20Storage.erc20Storage();

    require(msg.sender == ds.contractOwner, "Must own the contract.");

    LibERC20.mint(msg.sender, _initialSupply);

    es.name = _name;
    es.symbol = _symbol;
  }

  function name() external view override returns (string memory) {
    return LibERC20Storage.erc20Storage().name;
  }

  function symbol() external view override returns (string memory) {
    return LibERC20Storage.erc20Storage().symbol;
  }

  function decimals() external pure override returns (uint8) {
    return 18;
  }

  function mint(address _receiver, uint256 _amount) external override protectedCall {
    LibERC20.mint(_receiver, _amount);
  }

  function burn(address _from, uint256 _amount) external override protectedCall {
    LibERC20.burn(_from, _amount);
  }

  // SWC-114-Transaction Order Dependence: L53 - L61
  function approve(address _spender, uint256 _amount)
    external
    override
    returns (bool)
  {
    LibERC20Storage.erc20Storage().allowances[msg.sender][_spender] = _amount;
    emit Approval(msg.sender, _spender, _amount);
    return true;
  }

  function transfer(address _to, uint256 _amount)
    external
    override
    returns (bool)
  {
    _transfer(msg.sender, _to, _amount);
    return true;
  }

  function transferFrom(
    address _from,
    address _to,
    uint256 _amount
  ) external override returns (bool) {
    LibERC20Storage.ERC20Storage storage es = LibERC20Storage.erc20Storage();

    // Update approval if not set to max uint256
    if (es.allowances[_from][msg.sender] != uint256(-1)) {
      uint256 newApproval = es.allowances[_from][msg.sender].sub(_amount);
      es.allowances[_from][msg.sender] = newApproval;
      emit Approval(_from, msg.sender, newApproval);
    }

    _transfer(_from, _to, _amount);
  }

  function allowance(address _owner, address _spender)
    external
    view
    override
    returns (uint256)
  {
    return LibERC20Storage.erc20Storage().allowances[_owner][_spender];
  }

  function balanceOf(address _of) external view override returns (uint256) {
    return LibERC20Storage.erc20Storage().balances[_of];
  }

  function totalSupply() external view override returns (uint256) {
    return LibERC20Storage.erc20Storage().totalSupply;
  }

  function _transfer(
    address _from,
    address _to,
    uint256 _amount
  ) internal {
    if (_to == address(0)) {
      return LibERC20.burn(msg.sender, _amount);
    }
    LibERC20Storage.ERC20Storage storage es = LibERC20Storage.erc20Storage();

    es.balances[_from] = es.balances[_from].sub(_amount);
    es.balances[_to] = es.balances[_to].add(_amount);

    emit Transfer(_from, _to, _amount);
  }
}