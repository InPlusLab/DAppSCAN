pragma solidity ^0.4.24;

import "../utils/Ownable.sol";
import "../project/ProjectWalletAuthoriser.sol";

contract AuthContract is Ownable {

    address[]  public  members;
    uint       public  quorum;

    mapping (uint => mapping (address => bool)) public  confirmedBy;
    mapping (address => bool) public  isMember;
    mapping (bytes32 => Action) public actions;

    struct Action {
        address  target;
        address  sender;
        address  receiver;
        uint256  amt;

        uint     confirmations;
        bool     triggered;
    }

    event Confirmed  (bytes32 id, address member);
    event Triggered  (bytes32 id);

    constructor(address[] _members, uint _quorum) public {
        members = _members;
        quorum = _quorum;

        for (uint i = 0; i < members.length; i++) {
            isMember[members[i]] = true;
        }
    }

    /**
    * @dev Throws if called by a non-member.
    */
    modifier onlyMembers() {
        require(isMember[msg.sender], "Not a member");
        _;
    }

    modifier onlyActive(bytes32 _tx) {
        require(!actions[_tx].triggered, "Transaction already triggered");
        _;
    }

    function memberCount() public view returns (uint) {
        return members.length;
    }

    function setQuorum(uint _quorum) public onlyOwner {
        quorum = _quorum;
    }

    function validate(
        bytes32  _tx,
        address  _target,
        address  _sender,
        address  _receiver,
        uint256  _amt
    ) public onlyMembers returns (bool) {
        require(_tx != 0, "Invalid transaction id");
        require(_target != address(0), "Invalid target");
        require(_sender != address(0), "Invalid sender");
        require(_receiver != address(0), "Invalid receiver");
        require(_amt >= 0, "Invalid amount");
        actions[_tx].target = _target;
        actions[_tx].sender = _sender;
        actions[_tx].receiver = _receiver;
        actions[_tx].amt = _amt;
        actions[_tx].triggered = false;
        actions[_tx].confirmations = actions[_tx].confirmations + 1;

        emit Confirmed(_tx, msg.sender);

        if(actions[_tx].confirmations >= quorum){
            _trigger(_tx);
            emit Triggered(_tx);
        }

        return true;
    }

    function _trigger(bytes32 _tx) internal onlyMembers onlyActive(_tx) {
        actions[_tx].triggered = true;
        ProjectWalletAuthoriser(actions[_tx].target).transfer(actions[_tx].sender, actions[_tx].receiver, actions[_tx].amt);
    }

}
