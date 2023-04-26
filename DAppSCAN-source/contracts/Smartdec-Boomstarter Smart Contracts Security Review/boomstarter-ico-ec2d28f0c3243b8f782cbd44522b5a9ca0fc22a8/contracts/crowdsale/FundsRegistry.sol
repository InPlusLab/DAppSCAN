pragma solidity 0.4.23;

import 'mixbytes-solidity/contracts/ownership/MultiownedControlled.sol';
import 'mixbytes-solidity/contracts/security/ArgumentsChecker.sol';
import 'zeppelin-solidity/contracts/math/SafeMath.sol';
import 'zeppelin-solidity/contracts/ReentrancyGuard.sol';
import '../IBoomstarterToken.sol';


/// @title registry of funds sent by investors
contract FundsRegistry is ArgumentsChecker, MultiownedControlled, ReentrancyGuard {
    using SafeMath for uint256;

    enum State {
        // gathering funds
        GATHERING,
        // returning funds to investors
        REFUNDING,
        // funds can be pulled by owners
        SUCCEEDED
    }

    event StateChanged(State _state);
    event Invested(address indexed investor, uint etherInvested, uint tokensReceived);
    event EtherSent(address indexed to, uint value);
    event RefundSent(address indexed to, uint value);


    modifier requiresState(State _state) {
        require(m_state == _state);
        _;
    }


    // PUBLIC interface

    function FundsRegistry(
        address[] _owners,
        uint _signaturesRequired,
        address _controller,
        address _token
    )
        MultiownedControlled(_owners, _signaturesRequired, _controller)
    {
        m_token = IBoomstarterToken(_token);
    }

    /// @dev performs only allowed state transitions
    function changeState(State _newState)
        external
        onlyController
    {
        assert(m_state != _newState);

        if (State.GATHERING == m_state) {   assert(State.REFUNDING == _newState || State.SUCCEEDED == _newState); }
        else assert(false);

        m_state = _newState;
        StateChanged(m_state);
    }

    /// @dev records an investment
    /// @param _investor who invested
    /// @param _tokenAmount the amount of token bought, calculation is handled by ICO
    function invested(address _investor, uint _tokenAmount)
        external
        payable
        onlyController
        requiresState(State.GATHERING)
    {
        uint256 amount = msg.value;
        require(0 != amount);
        assert(_investor != m_controller);

        // register investor
        if (0 == m_weiBalances[_investor])
            m_investors.push(_investor);

        // register payment
        totalInvested = totalInvested.add(amount);
        m_weiBalances[_investor] = m_weiBalances[_investor].add(amount);
        m_tokenBalances[_investor] = m_tokenBalances[_investor].add(_tokenAmount);

        Invested(_investor, amount, _tokenAmount);
    }

    /// @notice owners: send `value` of ether to address `to`, can be called if crowdsale succeeded
    /// @param to where to send ether
    /// @param value amount of wei to send
    function sendEther(address to, uint value)
        external
        validAddress(to)
        onlymanyowners(keccak256(msg.data))
        requiresState(State.SUCCEEDED)
    {
        require(value > 0 && this.balance >= value);
        to.transfer(value);
        EtherSent(to, value);
    }

    /// @notice owners: send `value` of tokens to address `to`, can be called if
    ///         crowdsale failed and some of the investors refunded the ether
    /// @param to where to send tokens
    /// @param value amount of token-wei to send
    function sendTokens(address to, uint value)
        external
        validAddress(to)
        onlymanyowners(keccak256(msg.data))
        requiresState(State.REFUNDING)
    {
        require(value > 0 && m_token.balanceOf(this) >= value);
        m_token.transfer(to, value);
    }

    /// @notice withdraw accumulated balance, called by payee in case crowdsale failed
    /// @dev caller should approve tokens bought during ICO to this contract
    function withdrawPayments()
        external
        nonReentrant
        requiresState(State.REFUNDING)
    {
        address payee = msg.sender;
        uint payment = m_weiBalances[payee];
        uint tokens = m_tokenBalances[payee];

        // check that there is some ether to withdraw
        require(payment != 0);
        // check that the contract holds enough ether
        require(this.balance >= payment);
        // check that the investor (payee) gives back all tokens bought during ICO
        require(m_token.allowance(payee, this) >= m_tokenBalances[payee]);

        totalInvested = totalInvested.sub(payment);
        m_weiBalances[payee] = 0;
        m_tokenBalances[payee] = 0;

        m_token.transferFrom(payee, this, tokens);

        payee.transfer(payment);
        RefundSent(payee, payment);
    }

    function getInvestorsCount() external constant returns (uint) { return m_investors.length; }

    // FIELDS

    /// @notice total amount of investments in wei
    uint256 public totalInvested;

    /// @notice state of the registry
    State public m_state = State.GATHERING;

    /// @dev balances of investors in wei
    mapping(address => uint256) public m_weiBalances;

    /// @dev balances of tokens sold to investors
    mapping(address => uint256) public m_tokenBalances;

    /// @dev list of unique investors
    address[] public m_investors;

    /// @dev token accepted for refunds
    IBoomstarterToken public m_token;
}
