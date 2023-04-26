pragma solidity ^0.5.0;

import "openzeppelin-solidity/contracts/utils/Address.sol";
import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/token/ERC777/IERC777.sol";
import "openzeppelin-solidity/contracts/token/ERC777/IERC777Recipient.sol";
import "openzeppelin-solidity/contracts/token/ERC777/IERC777Sender.sol";
import "erc1820/contracts/ERC1820Client.sol";


contract TestERC777Only is
    IERC777,
    Ownable,
    ERC1820Client
{
    using Address for address;
    using SafeMath for uint;

    string public name;
    string public symbol;
    uint public totalSupply;

    mapping(address => uint) public balanceOf;
    mapping(address => mapping(address => bool)) private userToOperatorEnabled;

    constructor() public {
        name = "TestERC777Only";
        symbol = "E7O";
        setInterfaceImplementation("ERC777Token", address(this));
    }

    function granularity() public view returns (uint) { return 1; }

    function defaultOperators() external view returns (address[] memory) {return new address[](0);}

    function send(address _to, uint _amount, bytes memory _userData) public {
        _send(msg.sender, _to, _amount, _userData, msg.sender, "", true);
    }

    function authorizeOperator(address _operator) public {
        require(_operator != msg.sender, "NOT_YOURSELF");
        userToOperatorEnabled[_operator][msg.sender] = true;
        emit AuthorizedOperator(_operator, msg.sender);
    }

    function revokeOperator(address _operator) public {
        require(_operator != msg.sender, "NOT_YOURSELF");
        userToOperatorEnabled[_operator][msg.sender] = false;
        emit RevokedOperator(_operator, msg.sender);
    }


    function isOperatorFor(address _operator, address _tokenHolder) public view returns (bool) {
        return _operator == _tokenHolder || userToOperatorEnabled[_operator][_tokenHolder];
    }

    function operatorSend(address _from, address _to, uint _amount, bytes memory _userData, bytes memory _operatorData) public {
        require(isOperatorFor(msg.sender, _from), "NOT_AUTHORIZED");
        _send(_from, _to, _amount, _userData, msg.sender, _operatorData, true);
    }

    function mint(address _tokenHolder, uint _amount) public onlyOwner {
        totalSupply = totalSupply.add(_amount);
        balanceOf[_tokenHolder] = balanceOf[_tokenHolder].add(_amount);

        _callRecipient(msg.sender, address(0), _tokenHolder, _amount, "", "", true);

        emit Minted(msg.sender, _tokenHolder, _amount, "", "");
    }

    function burn(uint256 _amount, bytes memory _userData) public {
        _callSender(msg.sender, msg.sender, address(0), _amount, _userData, "");

        require(balanceOf[msg.sender] >= _amount, "INSUFFICIENT_BALANCE");

        balanceOf[msg.sender] = balanceOf[msg.sender].sub(_amount);
        totalSupply = totalSupply.sub(_amount);

        emit Burned(msg.sender, msg.sender, _amount, _userData, "");
    }

    function operatorBurn(address _tokenHolder, uint256 _amount, bytes memory _userData, bytes memory _operatorData) public {
        require(isOperatorFor(msg.sender, _tokenHolder), "NOT_AUTHORIZED");

        _callSender(msg.sender, _tokenHolder, address(0), _amount, _userData, _operatorData);

        require(balanceOf[_tokenHolder] >= _amount, "INSUFFICIENT_BALANCE");

        balanceOf[_tokenHolder] = balanceOf[_tokenHolder].sub(_amount);
        totalSupply = totalSupply.sub(_amount);

        emit Burned(msg.sender, _tokenHolder, _amount, _userData, _operatorData);
    }

    function _send(
        address _from,
        address _to,
        uint _amount,
        bytes memory _userData,
        address _operator,
        bytes memory _operatorData,
        bool _preventLocking
    ) private {
        _callSender(_operator, _from, _to, _amount, _userData, _operatorData);

        require(_to != address(0), "SENT_TO_0");
        require(balanceOf[_from] >= _amount, "INSUFFICIENT_BALANCE");

        balanceOf[_from] = balanceOf[_from].sub(_amount);
        balanceOf[_to] = balanceOf[_to].add(_amount);

        _callRecipient(_operator, _from, _to, _amount, _userData, _operatorData, _preventLocking);

        emit Sent(_operator, _from, _to, _amount, _userData, _operatorData);
    }

    function _callRecipient(
        address _operator,
        address _from,
        address _to,
        uint _amount,
        bytes memory _userData,
        bytes memory _operatorData,
        bool _preventLocking
    ) private {
        address recipientImplementation = interfaceAddr(_to, "ERC777TokensRecipient");
        if (recipientImplementation != address(0)) {
            IERC777Recipient(recipientImplementation).tokensReceived(
                _operator, _from, _to, _amount, _userData, _operatorData);
        } else if (_preventLocking) {
            require(!_to.isContract(), "CONTRACT_MISSING_RECEIVER");
        }
    }

    function _callSender(
        address _operator,
        address _from,
        address _to,
        uint _amount,
        bytes memory _userData,
        bytes memory _operatorData
    ) private {
        address senderImplementation = interfaceAddr(_from, "ERC777TokensSender");
        if (senderImplementation != address(0)) {
            IERC777Sender(senderImplementation).tokensToSend(
                _operator, _from, _to, _amount, _userData, _operatorData);
        }
    }
}
