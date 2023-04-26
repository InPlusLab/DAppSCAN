pragma solidity ^0.4.24;

import '../openzeppelin-solidity/contracts/token/ERC20/StandardToken.sol';

import '../openzeppelin-solidity/contracts/token/ERC20/ERC20.sol';
import '../openzeppelin-solidity/contracts/ownership/Ownable.sol';
import '../openzeppelin-solidity/contracts/math/SafeMath.sol';

import './interfaces/IDecentralizedNation.sol';
import "./libraries/GetCode.sol";

contract TwoKeyVoteToken is StandardToken, Ownable {
    using SafeMath for uint256;

    mapping (address => mapping (address => uint256)) internal allowed;
    mapping(address => uint256) internal balances;

    string public name = 'TwoKeyVote';
    string public symbol = '2KV';
    uint8 public decimals = 18;

    address public decentralizedNation;

    constructor(address _decentralizedNation) Ownable() public {
        require(_decentralizedNation!= address(0));
        decentralizedNation = _decentralizedNation;
    }

    mapping(address => bool) private visited;
    ///Mapping contract bytecode to boolean if is allowed to transfer tokens
    mapping(bytes32 => bool) private canEmit;

    /// @notice function where admin or any authorized person (will be added if needed) can add more contracts to allow them call methods
    /// @param _contractAddress is actually the address of contract we'd like to allow
    /// @dev We first fetch bytes32 contract code and then update our mapping
    /// @dev only admin can call this or an authorized person
    function addContract(address _contractAddress) public onlyOwner {
        require(_contractAddress != address(0), 'addContract zero');
        bytes memory _contractCode = GetCode.at(_contractAddress);
        bytes32 cc = keccak256(abi.encodePacked(_contractCode));
        canEmit[cc] = true;
    }


    ///@notice Modifier which will only allow allowed contracts to transfer tokens
    function allowedContract() private view returns (bool) {
        //just to use contract code instead of msg.sender address
        bytes memory code = GetCode.at(msg.sender);
        bytes32 cc = keccak256(abi.encodePacked(code));
        return canEmit[cc];
        return true;
    }

    modifier onlyAllowedContracts {
        require(allowedContract(), 'onlyAllowedContracts');
        _;
    }


    /**
    * @dev Gets the balance of the specified address.
    * @param _owner The address to query the the balance of.
    * @return An uint256 representing the amount owned by the passed address.
    */
    /*

    */
    function balanceOf(address _owner) public view returns (uint256) {
        if (visited[_owner]) {
            return balances[_owner];
        } else {
            uint id = IDecentralizedNation(decentralizedNation).getMemberid(_owner);
            if(id != 0) {
                uint balance = IDecentralizedNation(decentralizedNation).getMembersVotingPoints(_owner);
                return balance;
            } else {
                return 0;
            }
        }
    }

    function checkBalance(address _owner) internal returns (uint256){
        if (visited[_owner]) {
            return balances[_owner];
        }

        visited[_owner] = true;
        uint id = IDecentralizedNation(decentralizedNation).getMemberid(_owner);
        if(id != 0) {
             balances[_owner] = IDecentralizedNation(decentralizedNation).getMembersVotingPoints(_owner);
        }
        return balances[_owner];
    }

//    function balanceOf(address _owner) public view returns (uint256) {
//        uint balance = IDecentralizedNation(decentralizedNation).getMembersVotingPoints(_owner);
//        return balance;
//    }
//
//    function checkBalance(address _owner) public {
//        balances[_owner] = IDecentralizedNation(decentralizedNation).getMembersVotingPoints(_owner);
//    }
    /**
     * @dev Transfer tokens from one address to another
     * @param _from address The address which you want to send tokens from
     * @param _to address The address which you want to transfer to
     * @param _value uint256 the amount of tokens to be transferred
     */
    function transferFrom(
        address _from,
        address _to,
        uint256 _value
    )
    public
//        onlyOwner
    returns (bool)
    {
        checkBalance(_from);
        uint balance = balanceOf(_from);
        require(_value <= balance, 'transferFrom balance');
        require(_to != address(0), 'transferFrom zero');
        //TODO : reduce balance on contract
        balances[_from] = balances[_from].sub(_value);
        balances[_to] = balances[_to].add(_value);
        emit Transfer(_from, _to, _value);
        return true;
    }


    /**
     * @dev Function to check the amount of tokens that an owner allowed to a spender.
     * @param _owner address The address which owns the funds.
     * @return A uint256 specifying the amount of tokens still available for the spender.
     */
    function allowance(
        address _owner,
        address _spender
    )
    public
    view
    returns (uint256)
    {
        return balanceOf(_owner);
    }



    /**
    * @dev Total number of tokens in existence
    */
    function totalSupply() public view returns (uint256) {
        revert("totalSupply - not supported");
        return 0;
    }

    /**
    * @dev Transfer token for a specified address
    */
    function transfer(address, uint256) public returns (bool) {
        revert("transfer - not supported");
        return false;
    }

    function approve(address, uint256) public returns (bool) {
        revert("approve - not supported");
        return false;
    }
}
