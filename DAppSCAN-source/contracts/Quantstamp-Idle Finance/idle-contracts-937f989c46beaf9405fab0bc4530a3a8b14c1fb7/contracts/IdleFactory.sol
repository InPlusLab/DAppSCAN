/**
 * @title: Idle Factory contract
 * @summary: Used for deploying and keeping track of IdleTokens instances
 * @author: William Bergamo, idle.finance
 */
pragma solidity 0.5.11;

import "@openzeppelin/contracts/ownership/Ownable.sol";
import "./IdleToken.sol";

contract IdleFactory is Ownable {
  // tokenAddr (eg. DAI add) => idleTokenAddr (eg. idleDAI)
  mapping (address => address) public underlyingToIdleTokenMap;
  // array of underlying token addresses (eg. [DAIAddr, USDCAddr])
  address[] public tokensSupported;

  /**
   * Used to deploy new instances of IdleTokens, only callable by owner
   * Ownership of IdleToken is then transferred to msg.sender. Same for Pauser role
   *
   * @param _name : IdleToken name
   * @param _symbol : IdleToken symbol
   * @param _decimals : IdleToken decimals
   * @param _token : underlying token address
   * @param _cToken : cToken address
   * @param _iToken : iToken address
   * @param _rebalancer : Idle Rebalancer address
   * @param _idleCompound : Idle Compound address
   * @param _idleFulcrum : Idle Fulcrum address
   *
   * @return : newly deployed IdleToken address
   */
  function newIdleToken(
    string calldata _name, // eg. IdleDAI
    string calldata _symbol, // eg. IDLEDAI
    uint8 _decimals, // eg. 18
    address _token,
    address _cToken,
    address _iToken,
    address _rebalancer,
    address _priceCalculator,
    address _idleCompound,
    address _idleFulcrum
  ) external onlyOwner returns(address) {
    IdleToken idleToken = new IdleToken(
      _name, // eg. IdleDAI
      _symbol, // eg. IDLEDAI
      _decimals, // eg. 18
      _token,
      _cToken,
      _iToken,
      _rebalancer,
      _priceCalculator,
      _idleCompound,
      _idleFulcrum
    );
    if (underlyingToIdleTokenMap[_token] == address(0)) {
      tokensSupported.push(_token);
    }
    underlyingToIdleTokenMap[_token] = address(idleToken);

    return address(idleToken);
  }

  /**
  * Used to transfer ownership and the ability to pause from IdleFactory to owner
  *
  * @param _idleToken : idleToken address who needs to change owner and pauser
  */
  function setTokenOwnershipAndPauser(address _idleToken) external onlyOwner {
    IdleToken idleToken = IdleToken(_idleToken);
    idleToken.transferOwnership(msg.sender);
    idleToken.addPauser(msg.sender);
    idleToken.renouncePauser();
  }

  /**
  * @return : array of supported underlying tokens
  */
  function supportedTokens() external view returns(address[] memory) {
    return tokensSupported;
  }

  /**
  * @param _underlying : token address which maps to IdleToken address
  * @return : IdleToken address for that _underlying
  */
  function getIdleTokenAddress(address _underlying) external view returns(address) {
    return underlyingToIdleTokenMap[_underlying];
  }
}
