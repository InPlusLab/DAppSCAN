pragma solidity >=0.4.24;

import "./AkropolisBaseToken.sol";
import "../helpers/Lockable.sol";
import "../helpers/Pausable.sol";
import "../helpers/Whitelist.sol";


/**
* @title AkropolisToken
* @notice Adds pausability and disables approve() to defend against double-spend attacks in addition
* to inherited AkropolisBaseToken behavior
*/
contract AkropolisToken is AkropolisBaseToken, Pausable, Lockable, Whitelist {
    using SafeMath for uint256;

    /** Events */

    constructor (address _balances, address _allowances, string _name, uint8 _decimals, string _symbol) public 
    AkropolisBaseToken(_balances, _allowances, _name, _decimals, _symbol) {}

    /** Modifiers **/

    /** Functions **/

    function mint(address _to, uint256 _amount) public whenUnlocked  {
        super.mint(_to, _amount);
    }

    function burn(uint256 _amount) public whenUnlocked  {
        super.burn(_amount);
    }

    /**
    * @notice Implements ERC-20 standard approve function. Locked or disabled by default to protect against
    * double spend attacks. To modify allowances, clients should call safer increase/decreaseApproval methods.
    * Upon construction, all calls to approve() will revert unless this contract owner explicitly unlocks approve()
    */
    // SWC-113-DoS with Failed Call: L42
    function approve(address _spender, uint256 _value) 
    public whenNotPaused  whenUnlocked returns (bool) {
        return super.approve(_spender, _value);
    }

    /**
     * @dev Increase the amount of tokens that an owner allowed to a spender.
     * @notice increaseApproval should be used instead of approve when the user's allowance
     * is greater than 0. Using increaseApproval protects against potential double-spend attacks
     * by moving the check of whether the user has spent their allowance to the time that the transaction 
     * is mined, removing the user's ability to double-spend
     * @param _spender The address which will spend the funds.
     * @param _addedValue The amount of tokens to increase the allowance by.
     */
    function increaseApproval(address _spender, uint256 _addedValue) 
    public whenNotPaused returns (bool) {
        increaseApprovalAllArgs(_spender, _addedValue, msg.sender);
        return true;
    }

    /**
     * @dev Decrease the amount of tokens that an owner allowed to a spender.
     * @notice decreaseApproval should be used instead of approve when the user's allowance
     * is greater than 0. Using decreaseApproval protects against potential double-spend attacks
     * by moving the check of whether the user has spent their allowance to the time that the transaction 
     * is mined, removing the user's ability to double-spend
     * @param _spender The address which will spend the funds.
     * @param _subtractedValue The amount of tokens to decrease the allowance by.
     */
    function decreaseApproval(address _spender, uint256 _subtractedValue) 
    public whenNotPaused returns (bool) {
        decreaseApprovalAllArgs(_spender, _subtractedValue, msg.sender);
        return true;
    }

    // SWC-113-DoS with Failed Call: L77
    function transfer(address _to, uint256 _amount) public whenNotPaused onlyWhitelist checkPermBalanceForWhitelist(_amount) returns (bool) {
        return super.transfer(_to, _amount);
    }

    /**
    * @notice Initiates a transfer operation between address `_from` and `_to`. Requires that the
    * message sender is an approved spender on the _from account.
    * @dev When implemented, it should use the transferFromConditionsRequired() modifier.
    * @param _to The address of the recipient. This address must not be blacklisted.
    * @param _from The address of the origin of funds. This address _could_ be blacklisted, because
    * a regulator may want to transfer tokens out of a blacklisted account, for example.
    * In order to do so, the regulator would have to add themselves as an approved spender
    * on the account via `addBlacklistAddressSpender()`, and would then be able to transfer tokens out of it.
    * @param _amount The number of tokens to transfer
    * @return `true` if successful 
    */
    // SWC-113-DoS with Failed Call: L95
    function transferFrom(address _from, address _to, uint256 _amount) 
    public whenNotPaused onlyWhitelist checkPermBalanceForWhitelist(_amount) returns (bool) {
        return super.transferFrom(_from, _to, _amount);
    }


    /** Internal functions **/
    
    function decreaseApprovalAllArgs(address _spender, uint256 _subtractedValue, address _tokenHolder) internal {
        uint256 oldValue = allowances.allowanceOf(_tokenHolder, _spender);
        if (_subtractedValue > oldValue) {
            allowances.setAllowance(_tokenHolder, _spender, 0);
        } else {
            allowances.subAllowance(_tokenHolder, _spender, _subtractedValue);
        }
        emit Approval(_tokenHolder, _spender, allowances.allowanceOf(_tokenHolder, _spender));
    }

    function increaseApprovalAllArgs(address _spender, uint256 _addedValue, address _tokenHolder) internal {
        allowances.addAllowance(_tokenHolder, _spender, _addedValue);
        emit Approval(_tokenHolder, _spender, allowances.allowanceOf(_tokenHolder, _spender));
    }
}