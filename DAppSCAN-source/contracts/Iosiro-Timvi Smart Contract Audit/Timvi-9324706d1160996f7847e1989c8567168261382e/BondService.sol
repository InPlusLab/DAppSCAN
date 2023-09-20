pragma solidity 0.5.11;

import "../../helpers/SafeMath.sol";
import "../../helpers/IToken.sol";
import "../../helpers/ISettings.sol";
import "../../helpers/ILogic.sol";
import "../../helpers/IOracle.sol";


/// @title BondService
contract BondService {
    using SafeMath for uint256;

    /// @notice The address of the admin account.
    address public admin;

    // The amount of Ether received from the commissions of the system.
    uint256 systemETH;
//SWC-108-State Variable Default Visibility:L18
    // Commission percentage charged from the emitter
    uint256 public emitterFee;

    // Commission percentage charged from the owner
    uint256 public ownerFee;

    // The percentage divider
    uint256 public divider = 100000;

    // The minimum deposit amount
    uint256 public minEther;

    // The settings contract address
    ISettings public settings;

    /// @dev An array containing the Bond struct for all Bonds in existence. The ID
    ///  of each Bond is actually an index into this array.
    Bond[] public bonds;

    /// @dev The main Bond struct. Every Bond is represented by a copy
    ///  of this structure.
    struct Bond {
        // The address of the emitter of the Bond
        address payable emitter;
        // The address of the owner of the Bond
        address         owner;
        // The Ether amount packed in the Bond
        uint256         deposit;
        // The collateral percentage
        uint256         percent;
        // The number of TMV tokens withdrawn to owner
        uint256         tmv;
        // The expiration time in seconds
        uint256         expiration;
        // The percentage of the owner commission fee
        uint256         yearFee;
        // The percentage of the system commission fee
        uint256         sysFee;
        // The TBox ID created inside the Bond
        uint256         tBoxId;
        // The timestamp of the Bond creation
        // Sets at the matching moment
        uint256         createdAt;
    }


    /// @dev The BondCreated event is fired whenever a new Bond comes into existence.
    event BondCreated(uint256 id, address who, uint256 deposit, uint256 percent, uint256 expiration, uint256 yearFee);

    /// @dev The BondChanged event is fired whenever a Bond changing.
    event BondChanged(uint256 id, uint256 deposit, uint256 percent, uint256 expiration, uint256 yearFee, address who);

    /// @dev The BondClosed event is fired whenever a Bond is closed.
    event BondClosed(uint256 id, address who);

    /// @dev The BondMatched event is fired whenever a Bond is matched.
    event BondMatched(uint256 id, address who, uint256 tBox, uint256 tmv, uint256 sysFee, address counteragent);

    /// @dev The BondFinished event is fired whenever a Bond is finished.
    event BondFinished(uint256 id, address emitter, address owner);

    /// @dev The BondExpired event is fired whenever a Bond is expired.
    event BondExpired(uint256 id, address emitter, address owner);

    event BondOwnerFeeUpdated(uint256 _value);
    event BondEmitterFeeUpdated(uint256 _value);
    event BondMinEtherUpdated(uint256 _value);

    /// @dev Access modifier for admin-only functionality.
    modifier onlyAdmin() {
        require(admin == msg.sender, "You have no access");
        _;
    }

    /// @dev Access modifier for emitter-only functionality.
    /// @param _id A Bond ID.
    modifier onlyEmitter(uint256 _id) {
        require(bonds[_id].emitter == msg.sender, "You are not the emitter");
        _;
    }

    /// @dev Access modifier for single owner-only functionality.
    /// @param _id A Bond ID.
    modifier singleOwner(uint256 _id) {
        bool _a = bonds[_id].emitter == msg.sender && bonds[_id].owner == address(0);
        bool _b = bonds[_id].owner == msg.sender && bonds[_id].emitter == address(0);
        require(_a || _b, "You are not the single owner");
        _;
    }

    /// @dev Modifier to allow actions only when the bond is emitter's request
    /// @param _id A Bond ID.
    modifier emitRequest(uint256 _id) {
        require(bonds[_id].emitter != address(0) && bonds[_id].owner == address(0), "The bond isn't an emit request");
        _;
    }

    /// @dev Modifier to allow actions only when the bond is owner's request
    /// @param _id A Bond ID.
    modifier buyRequest(uint256 _id) {
        require(bonds[_id].owner != address(0) && bonds[_id].emitter == address(0), "The bond isn't an buy request");
        _;
    }

    /// @dev Modifier to allow actions only when the bond is mathced
    /// @param _id A Bond ID.
    modifier matched(uint256 _id) {
        require(bonds[_id].emitter != address(0) && bonds[_id].owner != address(0), "Bond isn't matched");
        _;
    }

    /// @notice Settings address couldn't be changed later.
    /// @dev The contract constructor sets the original `admin` of the contract to the sender
    //   account and sets the settings contract with provided address.
    /// @param _settings The address of the settings contract.
    constructor(ISettings _settings) public {
        admin = msg.sender;
        settings = _settings;

        emitterFee = 500; // 0.5%
        emit BondEmitterFeeUpdated(emitterFee);

        ownerFee = 10000; // 10%
        emit BondOwnerFeeUpdated(ownerFee);

        minEther = 0.1 ether;
        emit BondMinEtherUpdated(minEther);
    }

    /// @dev Creates emitter request.
    /// @param _percent The collateral percentage.
    /// @param _expiration The expiration in seconds.
    /// @param _yearFee The percentage of the commission.
    /// @return New Bond ID.
    function leverage(uint256 _percent, uint256 _expiration, uint256 _yearFee) public payable returns (uint256) {
        require(msg.value >= minEther, "Too small funds");
        require(_percent >= ILogic(settings.logicManager()).withdrawPercent(msg.value), "Collateralization is not enough");
        require(_expiration >= 1 days && _expiration <= 365 days, "Expiration out of range");
        require(_yearFee <= 10000, "Fee out of range");

        return createBond(tx.origin, address(0), _percent, _expiration, _yearFee);
    }

    /// @dev Creates owner request.
    /// @param _expiration The expiration in seconds.
    /// @param _yearFee The percentage of the commission.
    /// @return New Bond ID.
    function exchange(uint256 _expiration, uint256 _yearFee) public payable returns (uint256) {
        require(msg.value >= minEther, "Too small funds");
        require(_expiration >= 1 days && _expiration <= 365 days, "Expiration out of range");
        require(_yearFee <= 10000, "Fee out of range");

        return createBond(address(0), tx.origin, 0, _expiration, _yearFee);
    }

    /// @dev Creates Bond request.
    /// @param _emitter The address of the emitter.
    /// @param _owner The address of the owner.
    /// @param _percent The collateral percentage.
    /// @param _expiration The expiration in seconds.
    /// @param _yearFee The percentage of the commission.
    /// @return New Bond ID.
    function createBond(
        address payable _emitter,
        address _owner,
        uint256 _percent,
        uint256 _expiration,
        uint256 _yearFee
    )
    internal
    returns(uint256)
    {
        Bond memory _bond = Bond(
            _emitter,
            _owner,
            msg.value,
            _percent,
            0,
            _expiration,
            _yearFee,
            0,
            0,
            0
        );
        uint256 _id = bonds.push(_bond).sub(1);
        emit BondCreated(_id, tx.origin, msg.value, _percent, _expiration, _yearFee);
        return _id;
    }

    /// @dev Closes the bond.
    /// @param _id A Bond ID.
    function close(uint256 _id) external singleOwner(_id) {
        uint256 _eth = bonds[_id].deposit;
        delete bonds[_id];
        msg.sender.transfer(_eth);
        emit BondClosed(_id, msg.sender);
    }

    /// @dev Changes the emitter request.
    /// @param _id A Bond ID.
    /// @param _deposit The collateral amount.
    /// @param _percent The collateral percentage.
    /// @param _expiration The expiration in seconds.
    /// @param _yearFee The percentage of the commission.
    function changeEmitter(uint256 _id, uint256 _deposit, uint256 _percent, uint256 _expiration, uint256 _yearFee)
        external
        payable
        singleOwner(_id)
        onlyEmitter(_id)
    {
        changeDeposit(_id, _deposit);
        changePercent(_id, _percent);
        changeExpiration(_id, _expiration);
        changeYearFee(_id, _yearFee);

        emit BondChanged(_id, _deposit, _percent, _expiration, _yearFee, msg.sender);
    }

    /// @dev Changes the owner request.
    /// @param _id A Bond ID.
    /// @param _deposit The collateral amount.
    /// @param _expiration The expiration in seconds.
    /// @param _yearFee The percentage of the commission.
    function changeOwner(uint256 _id, uint256 _deposit, uint256 _expiration, uint256 _yearFee)
        external
        payable
    {
        require(bonds[_id].owner == msg.sender && bonds[_id].emitter == address(0), "You are not the owner ot bond is matched");
        changeDeposit(_id, _deposit);
        changeExpiration(_id, _expiration);
        changeYearFee(_id, _yearFee);
        emit BondChanged(_id, _deposit, 0, _expiration, _yearFee, msg.sender);
    }

    function changeDeposit(uint256 _id, uint256 _deposit) internal {
        uint256 _oldDeposit = bonds[_id].deposit;
        if (_deposit != 0 && _oldDeposit != _deposit) {
            require(_deposit >= minEther, "Too small funds");
            bonds[_id].deposit = _deposit;
            if (_oldDeposit > _deposit) {
                msg.sender.transfer(_oldDeposit.sub(_deposit));
            } else {
                require(msg.value == _deposit.sub(_oldDeposit), "Incorrect value");
            }
        }
    }

    function changePercent(uint256 _id, uint256 _percent) internal {
        uint256 _oldPercent = bonds[_id].percent;
        if (_percent != 0 && _oldPercent != _percent) {
            require(_percent >= ILogic(settings.logicManager()).withdrawPercent(bonds[_id].deposit), "Collateralization is not enough");
            bonds[_id].percent = _percent;
        }
    }

    function changeExpiration(uint256 _id, uint256 _expiration) internal {
        uint256 _oldExpiration = bonds[_id].expiration;
        if (_oldExpiration != _expiration) {
            require(_expiration >= 1 days && _expiration <= 365 days, "Expiration out of range");
            bonds[_id].expiration = _expiration;
        }
    }

    function changeYearFee(uint256 _id, uint256 _yearFee) internal {
        uint256 _oldYearFee = bonds[_id].expiration;
        if (_oldYearFee != _yearFee) {
            require(_yearFee <= 10000, "Fee out of range");
            bonds[_id].yearFee = _yearFee;
        }
    }

    /// @dev Uses to match the emitter request.
    /// @param _id A Bond ID.
    function takeEmitRequest(uint256 _id) external payable emitRequest(_id) {

        address payable _emitter = bonds[_id].emitter;
        uint256 _eth = bonds[_id].deposit.mul(divider).div(bonds[_id].percent);

        require(msg.value == _eth, "Incorrect ETH value");

        uint256 _sysEth = _eth.mul(emitterFee).div(divider);
        systemETH = systemETH.add(_sysEth);

        uint256 _tmv = _eth.mul(rate()).div(precision());
        uint256 _box = ILogic(settings.logicManager()).create.value(bonds[_id].deposit)(_tmv);

        bonds[_id].owner = msg.sender;
        bonds[_id].tmv = _tmv;
        bonds[_id].expiration = bonds[_id].expiration.add(now);
        bonds[_id].sysFee = ownerFee;
        bonds[_id].tBoxId = _box;
        bonds[_id].createdAt = now;

        _emitter.transfer(_eth.sub(_sysEth));
        IToken(settings.tmvAddress()).transfer(msg.sender, _tmv);
        emit BondMatched(_id, msg.sender, _box, _tmv, ownerFee, _emitter);
    }

    /// @dev Uses to match the owner request.
    /// @param _id A Bond ID.
    function takeBuyRequest(uint256 _id) external payable buyRequest(_id) {

        address _owner = bonds[_id].owner;

        uint256 _sysEth = bonds[_id].deposit.mul(emitterFee).div(divider);
        systemETH = systemETH.add(_sysEth);

        uint256 _tmv = bonds[_id].deposit.mul(rate()).div(precision());
        uint256 _box = ILogic(settings.logicManager()).create.value(msg.value)(_tmv);

        bonds[_id].emitter = msg.sender;
        bonds[_id].tmv = _tmv;
        bonds[_id].expiration = bonds[_id].expiration.add(now);
        bonds[_id].sysFee = ownerFee;
        bonds[_id].tBoxId = _box;
        bonds[_id].createdAt = now;

        msg.sender.transfer(bonds[_id].deposit.sub(_sysEth));
        IToken(settings.tmvAddress()).transfer(_owner, _tmv);
        emit BondMatched(_id, msg.sender, _box, _tmv, ownerFee, _owner);
    }

    /// @dev Finishes the bond.
    /// @param _id A Bond ID.
    function finish(uint256 _id) external onlyEmitter(_id) {

        // It's not need to check matching of the bond
        // since the expiration period cannot exceed 365 days.
        require(now < bonds[_id].expiration, "Bond expired");

        uint256 _secondsPast = now.sub(bonds[_id].createdAt);
        (uint256 _eth, uint256 _debt) = getBox(bonds[_id].tBoxId);

        uint256 _commission = bonds[_id].tmv.mul(_secondsPast).mul(bonds[_id].yearFee).div(365 days).div(divider);
        uint256 _sysTMV = _commission.mul(bonds[_id].sysFee).div(divider);

        address _owner = bonds[_id].owner;

        if (_sysTMV.add(_debt) > 0)
            IToken(settings.tmvAddress()).transferFrom(msg.sender, address(this), _sysTMV.add(_debt));
        if (_commission > 0)
            IToken(settings.tmvAddress()).transferFrom(msg.sender, _owner, _commission.sub(_sysTMV));

        if (_eth > 0) {
            ILogic(settings.logicManager()).close(bonds[_id].tBoxId);
            delete bonds[_id];
            msg.sender.transfer(_eth);
        } else {
            // when TBox no longer exists
            delete bonds[_id];
        }

        emit BondFinished(_id, msg.sender, _owner);
    }

    /// @dev Executes expiration process of the bond.
    /// @param _id A Bond ID.
    function expire(uint256 _id) external matched(_id) {

        require(now > bonds[_id].expiration, "Bond hasn't expired");


        (uint256 _eth, uint256 _tmv) = getBox(bonds[_id].tBoxId);

        if (_eth == 0) {
            emit BondExpired(_id, bonds[_id].emitter, bonds[_id].owner);
            delete bonds[_id];
            return;
        }

        if (_tmv != 0)
            _eth = ILogic(settings.logicManager()).withdrawableEth(bonds[_id].tBoxId);

        uint256 _commission = _eth.mul(bonds[_id].sysFee).div(divider);

        if (_commission > 0)
            ILogic(settings.logicManager()).withdrawEth(bonds[_id].tBoxId, _commission);

        systemETH = systemETH.add(_commission);

        ILogic(settings.logicManager()).transferFrom(address(this), bonds[_id].owner, bonds[_id].tBoxId);

        emit BondExpired(_id, bonds[_id].emitter, bonds[_id].owner);

        delete bonds[_id];
    }

    /// @dev Returns TBox parameters.
    /// @param _id A Bond ID.
    function getBox(uint256 _id) public view returns(uint256, uint256) {
        return ILogic(settings.logicManager()).boxes(_id);
    }

    /// @dev Needs to claim funds from the logic contract to execute finishing and expiration.
    function() external payable {}

    /// @dev Withdraws system fee.
    /// @param _beneficiary The address to forward funds to.
    function withdrawSystemETH(address payable _beneficiary) external onlyAdmin {
        require(_beneficiary != address(0), "Zero address, be careful");
        require(systemETH > 0, "There is no available ETH");

        uint256 _systemETH = systemETH;
        systemETH = 0;
        _beneficiary.transfer(_systemETH);
    }

    /// @dev Reclaims ERC20 tokens.
    /// @param _token The address of the ERC20 token.
    /// @param _beneficiary The address to forward funds to.
    function reclaimERC20(address _token, address _beneficiary) external onlyAdmin {
        require(_beneficiary != address(0), "Zero address, be careful");

        uint256 _amount = IToken(_token).balanceOf(address(this));
        require(_amount > 0, "There are no tokens");
        IToken(_token).transfer(_beneficiary, _amount);
    }

    /// @dev Sets emitter fee.
    /// @param _value Commission percentage.
    function setEmitterFee(uint256 _value) external onlyAdmin {
        require(_value <= 10000, "Too much");
        emitterFee = _value;
        emit BondEmitterFeeUpdated(_value);
    }

    /// @dev Sets owner fee.
    /// @param _value Commission percentage.
    function setOwnerFee(uint256 _value) external onlyAdmin {
        require(_value <= 50000, "Too much");
        ownerFee = _value;
        emit BondOwnerFeeUpdated(_value);
    }

    /// @dev Sets minimum deposit amount.
    /// @param _value The minimum deposit amount in wei.
    function setMinEther(uint256 _value) external onlyAdmin {
        require(_value <= 100 ether, "Too much");
        minEther = _value;
        emit BondMinEtherUpdated(_value);
    }

    /// @dev Sets admin address.
    /// @param _newAdmin The address of the new admin.
    function changeAdmin(address _newAdmin) external onlyAdmin {
        require(_newAdmin != address(0), "Zero address, be careful");
        admin = _newAdmin;
    }

    /// @dev Returns precision using for USD and commission calculation.
    function precision() public view returns(uint256) {
        return ILogic(settings.logicManager()).precision();
    }

    /// @dev Returns current oracle ETH/USD price with precision.
    function rate() public view returns(uint256) {
        return IOracle(settings.oracleAddress()).ethUsdPrice();
    }
}
