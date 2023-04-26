pragma solidity 0.4.23;

import 'zeppelin-solidity/contracts/token/ERC20.sol';
import 'zeppelin-solidity/contracts/math/SafeMath.sol';


/// @title Example implementation of IApprovalRecipient interface - DONT use in production!
contract TestApprovalRecipient {
    using SafeMath for uint256;

    event ReceivedBytesLength(uint length);
    event ReceivedByte(byte b);

    function TestApprovalRecipient(ERC20 token) public {
        m_token = token;
    }

    function receiveApproval(address _sender, uint256 _value, bytes _extraData) public {
        // Validating origin of request - it must be a token contract we know and trust.
        require(msg.sender == address(m_token));

        // Receiving tokens.
        require(m_token.transferFrom(_sender, address(this), _value));

        // Performing some actions on behalf of token sender.
        m_bonuses[_sender] = m_bonuses[_sender].add(_value);

        // Looking into _extraData in some way. This parameter is optional in most cases.
        ReceivedBytesLength(_extraData.length);
        for (uint i = 0; i < _extraData.length; ++i)
            ReceivedByte(_extraData[i]);

        if (2 == _extraData.length && byte(0x40) == _extraData[0] && byte(0x41) == _extraData[1])
            m_bonuses[_sender] = m_bonuses[_sender].add(_value);
    }

    mapping(address => uint256) public m_bonuses;

    ERC20 private m_token;
}
