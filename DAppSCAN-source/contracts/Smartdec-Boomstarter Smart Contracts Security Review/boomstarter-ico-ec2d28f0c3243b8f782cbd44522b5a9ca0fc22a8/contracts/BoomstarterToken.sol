pragma solidity 0.4.23;

import 'zeppelin-solidity/contracts/token/StandardToken.sol';

import 'mixbytes-solidity/contracts/security/ArgumentsChecker.sol';
import 'mixbytes-solidity/contracts/ownership/multiowned.sol';

import './token/BurnableToken.sol';
import './token/TokenWithApproveAndCallMethod.sol';


/**
 * @title Boomstarter project token.
 *
 * Standard ERC20 burnable token plus logic to support token freezing for crowdsales.
 */
contract BoomstarterToken is ArgumentsChecker, multiowned, BurnableToken, StandardToken, TokenWithApproveAndCallMethod {

    // MODIFIERS

    /// @dev makes transfer possible if tokens are unfrozen OR if the caller is a sale account
    modifier saleOrUnfrozen(address account) {
        require( (m_frozen == false) || isSale(account) );
        _;
    }

    modifier onlySale(address account) {
        require(isSale(account));
        _;
    }

    modifier privilegedAllowed {
        require(m_allowPrivileged);
        _;
    }


    // PUBLIC FUNCTIONS

    /**
     * @notice Constructs token.
     *
     * @param _initialOwners initial multi-signatures, see comment below
     * @param _signaturesRequired quorum of multi-signatures
     *
     * Initial owners have power over the token contract only during bootstrap phase (early investments and token
     * sales). To be precise, the owners can set sales (which can transfer frozen tokens) during
     * bootstrap phase. After final token sale any control over the token removed by issuing disablePrivileged call.
     * For lifecycle example please see test/BootstarterTokenTest.js, 'test full lifecycle'.
     */
    function BoomstarterToken(address[] _initialOwners, uint _signaturesRequired)
        public
        multiowned(_initialOwners, _signaturesRequired)
    {
        totalSupply = MAX_SUPPLY;
        balances[msg.sender] = totalSupply;
        // mark initial owner as a sale to enable frozen transfer for them
        // as well as the option to set next sale without multi-signature
        m_sales[msg.sender] = true;
        Transfer(address(0), msg.sender, totalSupply);
    }

    /**
     * @notice Standard transfer() but with check of frozen status
     *
     * @param _to the address to transfer to
     * @param _value the amount to be transferred
     *
     * @return true iff operation was successfully completed
     */
    function transfer(address _to, uint256 _value)
        public
        saleOrUnfrozen(msg.sender)
        returns (bool)
    {
        return super.transfer(_to, _value);
    }

    /**
     * @notice Standard transferFrom but incorporating frozen tokens logic
     *
     * @param _from address the address which you want to send tokens from
     * @param _to address the address which you want to transfer to
     * @param _value uint256 the amount of tokens to be transferred
     *
     * @return true iff operation was successfully completed
     */
    function transferFrom(address _from, address _to, uint256 _value)
        public
        saleOrUnfrozen(msg.sender)
        returns (bool)
    {
        return super.transferFrom(_from, _to, _value);
    }

    /**
     * Function to burn msg.sender's tokens. Overridden to prohibit burning frozen tokens
     *
     * @param _amount amount of tokens to burn
     *
     * @return boolean that indicates if the operation was successful
     */
    function burn(uint256 _amount)
        public
        saleOrUnfrozen(msg.sender)
        returns (bool)
    {
        return super.burn(_amount);
    }

    // ADMINISTRATIVE FUNCTIONS

    /**
     * @notice Sets sale status of an account.
     *
     * @param account account address
     * @param isSale enables this account to transfer tokens in frozen state
     *
     * Function is used only during token sale phase, before disablePrivileged() is called.
     */
    function setSale(address account, bool isSale)
        external
        validAddress(account)
        privilegedAllowed
        onlymanyowners(keccak256(msg.data))
    {
        m_sales[account] = isSale;
    }

    /**
     * @notice Same as setSale, but must be called from the current active sale and
     *         doesn't need multisigning (it's done in the finishSale call anyway)
     */
    function switchToNextSale(address _nextSale)
        external
        validAddress(_nextSale)
        onlySale(msg.sender)
    {
        m_sales[msg.sender] = false;
        m_sales[_nextSale] = true;
    }

    /// @notice Make transfer of tokens available to everyone
    function thaw()
        external
        privilegedAllowed
        onlymanyowners(keccak256(msg.data))
    {
        m_frozen = false;
    }

    /// @notice Disables further use of privileged functions: setSale, thaw
    function disablePrivileged()
        external
        privilegedAllowed
        onlymanyowners(keccak256(msg.data))
    {
        // shouldn't be frozen otherwise will be impossible to unfreeze
        require( false == m_frozen );
        m_allowPrivileged = false;
    }


    // INTERNAL FUNCTIONS

    function isSale(address account) private view returns (bool) {
        return m_sales[account];
    }


    // FIELDS

    /// @notice set of sale accounts which can freeze tokens
    mapping (address => bool) public m_sales;

    /// @notice allows privileged functions (token sale phase)
    bool public m_allowPrivileged = true;

    /// @notice when true - all tokens are frozen and only sales can move their tokens
    ///         when false - all tokens are unfrozen and can be moved by their owners
    bool public m_frozen = true;

    // CONSTANTS

    string public constant name = "BoomstarterCoin";
    string public constant symbol = "BC";
    uint8 public constant decimals = 18;

    uint public constant MAX_SUPPLY = uint(36) * uint(1000000) * uint(10) ** uint(decimals);
}
