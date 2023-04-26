pragma solidity 0.4.25;

import "../../helpers/SafeMath.sol";
import "../../helpers/IToken.sol";
import "../../helpers/ISettings.sol";
import "../../helpers/ITBoxManager.sol";
import "../../helpers/IOracle.sol";


/// @title BondService
contract BondService {
    using SafeMath for uint256;

    /// @notice The address of the admin account.
    address public admin;

    // The amount of Ether received from the commissions of the system.
    uint256 private systemETH;

    // Commission percentage charged from the issuer
    uint256 public issuerFee;

    // Commission percentage charged from the holder
    uint256 public holderFee;

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
        // The address of the issuer of the Bond
        address issuer;
        // The address of the holder of the Bond
        address         holder;
        // The Ether amount packed in the Bond
        uint256         deposit;
        // The collateral percentage
        uint256         percent;
        // The number of TMV tokens withdrawn to holder
        uint256         tmv;
        // The expiration time in seconds
        uint256         expiration;
        // The percentage of the holder commission fee
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
    event BondFinished(uint256 id, address issuer, address holder);

    /// @dev The BondExpired event is fired whenever a Bond is expired.
    event BondExpired(uint256 id, address issuer, address holder);

    event BondHolderFeeUpdated(uint256 _value);
    event BondIssuerFeeUpdated(uint256 _value);
    event BondMinEtherUpdated(uint256 _value);
    event IssuerRightsTransferred(address indexed from, address indexed to, uint indexed id);
    event HolderRightsTransferred(address indexed from, address indexed to, uint indexed id);

    /// @dev Defends against front-running attacks.
    modifier validTx() {
        require(tx.gasprice <= settings.gasPriceLimit(), "Gas price is greater than allowed");
        _;
    }

    /// @dev Access modifier for admin-only functionality.
    modifier onlyAdmin() {
        require(admin == msg.sender, "You have no access");
        _;
    }

    /// @dev Access modifier for issuer-only functionality.
    /// @param _id A Bond ID.
    modifier onlyIssuer(uint256 _id) {
        require(bonds[_id].issuer == msg.sender, "You are not the issuer");
        _;
    }

    /// @dev Access modifier for holder-only functionality.
    /// @param _id A Bond ID.
    modifier onlyHolder(uint256 _id) {
        require(bonds[_id].holder == msg.sender, "You are not the holder");
        _;
    }

    /// @dev Access modifier for single-owner-only functionality.
    /// @param _id A Bond ID.
    modifier singleOwner(uint256 _id) {
        bool _a = bonds[_id].issuer == msg.sender && bonds[_id].holder == address(0);
        bool _b = bonds[_id].holder == msg.sender && bonds[_id].issuer == address(0);
        require(_a || _b, "You are not the single owner");
        _;
    }

    /// @dev Modifier to allow actions only when the bond is issuer's request
    /// @param _id A Bond ID.
    modifier issueRequest(uint256 _id) {
        require(bonds[_id].issuer != address(0) && bonds[_id].holder == address(0), "The bond isn't an emit request");
        _;
    }

    /// @dev Modifier to allow actions only when the bond is holder's request
    /// @param _id A Bond ID.
    modifier buyRequest(uint256 _id) {
        require(bonds[_id].holder != address(0) && bonds[_id].issuer == address(0), "The bond isn't a buy request");
        _;
    }

    /// @dev Modifier to allow actions only when the bond is matched
    /// @param _id A Bond ID.
    modifier matched(uint256 _id) {
        require(bonds[_id].issuer != address(0) && bonds[_id].holder != address(0), "Bond isn't matched");
        _;
    }

    /// @notice Settings address can't be changed later.
    /// @dev The contract constructor sets the original `admin` of the contract to the sender
    //   account and sets the settings contract with provided address.
    /// @param _settings The address of the settings contract.
    constructor(ISettings _settings) public {
        admin = msg.sender;
        settings = _settings;

        issuerFee = 500; // 0.5%
        emit BondIssuerFeeUpdated(issuerFee);

        holderFee = 10000; // 10%
        emit BondHolderFeeUpdated(holderFee);

        minEther = 0.1 ether;
        emit BondMinEtherUpdated(minEther);
    }

    /// @dev Creates issuer request.
    /// @param _percent The collateral percentage.
    /// @param _expiration The expiration in seconds.
    /// @param _yearFee The percentage of the commission.
    /// @return New Bond ID.
    function leverage(uint256 _percent, uint256 _expiration, uint256 _yearFee) public payable returns (uint256) {
        require(msg.value >= minEther, "Too small funds");
        require(_percent >= ITBoxManager(settings.tBoxManager()).withdrawPercent(msg.value), "Collateralization is not enough");
        require(_expiration >= 1 days && _expiration <= 365 days, "Expiration out of range");
        require(_yearFee <= 25000, "Fee out of range");

        return createBond(msg.sender, address(0), _percent, _expiration, _yearFee);
    }

    /// @dev Creates holder request.
    /// @param _expiration The expiration in seconds.
    /// @param _yearFee The percentage of the commission.
    /// @return New Bond ID.
    function exchange(uint256 _expiration, uint256 _yearFee) public payable returns (uint256) {
        require(msg.value >= minEther, "Too small funds");
        require(_expiration >= 1 days && _expiration <= 365 days, "Expiration out of range");
        require(_yearFee <= 25000, "Fee out of range");

        return createBond(address(0), msg.sender, 0, _expiration, _yearFee);
    }

    /// @dev Creates Bond request.
    /// @param _issuer The address of the issuer.
    /// @param _holder The address of the holder.
    /// @param _percent The collateral percentage.
    /// @param _expiration The expiration in seconds.
    /// @param _yearFee The percentage of the commission.
    /// @return New Bond ID.
    function createBond(
        address _issuer,
        address _holder,
        uint256 _percent,
        uint256 _expiration,
        uint256 _yearFee
    )
    internal
    returns(uint256)
    {
        Bond memory _bond = Bond(
            _issuer,
            _holder,
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
        emit BondCreated(_id, msg.sender, msg.value, _percent, _expiration, _yearFee);
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

    /// @dev Changes the issuer request.
    /// @param _id A Bond ID.
    /// @param _deposit The collateral amount.
    /// @param _percent The collateral percentage.
    /// @param _expiration The expiration in seconds.
    /// @param _yearFee The percentage of the commission.
    function issuerChange(uint256 _id, uint256 _deposit, uint256 _percent, uint256 _expiration, uint256 _yearFee)
        external
        payable
        singleOwner(_id)
        onlyIssuer(_id)
    {
        changeDeposit(_id, _deposit);
        changePercent(_id, _percent);
        changeExpiration(_id, _expiration);
        changeYearFee(_id, _yearFee);

        emit BondChanged(_id, _deposit, _percent, _expiration, _yearFee, msg.sender);
    }

    /// @dev Changes the holder request.
    /// @param _id A Bond ID.
    /// @param _deposit The collateral amount.
    /// @param _expiration The expiration in seconds.
    /// @param _yearFee The percentage of the commission.
    function holderChange(uint256 _id, uint256 _deposit, uint256 _expiration, uint256 _yearFee)
        external
        payable
    {
        require(bonds[_id].holder == msg.sender && bonds[_id].issuer == address(0), "You are not the holder or bond is matched");
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
            require(_percent >= ITBoxManager(settings.tBoxManager()).withdrawPercent(bonds[_id].deposit), "Collateralization is not enough");
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
        uint256 _oldYearFee = bonds[_id].yearFee;
        if (_oldYearFee != _yearFee) {
            require(_yearFee <= 25000, "Fee out of range");
            bonds[_id].yearFee = _yearFee;
        }
    }

    /// @dev Uses to match the issuer request.
    /// @param _id A Bond ID.
    function takeIssueRequest(uint256 _id) external payable issueRequest(_id) validTx {

        address _issuer = bonds[_id].issuer;
        uint256 _eth = bonds[_id].deposit.mul(divider).div(bonds[_id].percent);

        require(msg.value == _eth, "Incorrect ETH value");

        uint256 _sysEth = _eth.mul(issuerFee).div(divider);
        systemETH = systemETH.add(_sysEth);

        uint256 _tmv = _eth.mul(rate()).div(precision());
        uint256 _box = ITBoxManager(settings.tBoxManager()).create.value(bonds[_id].deposit)(_tmv);

        bonds[_id].holder = msg.sender;
        bonds[_id].tmv = _tmv;
        bonds[_id].expiration = bonds[_id].expiration.add(now);
        bonds[_id].sysFee = holderFee;
        bonds[_id].tBoxId = _box;
        bonds[_id].createdAt = now;

        _issuer.transfer(_eth.sub(_sysEth));
        IToken(settings.tmvAddress()).transfer(msg.sender, _tmv);
        emit BondMatched(_id, msg.sender, _box, _tmv, holderFee, _issuer);
    }

    /// @dev Uses to match the holder request.
    /// @param _id A Bond ID.
    function takeBuyRequest(uint256 _id) external payable buyRequest(_id) validTx {

        address _holder = bonds[_id].holder;

        uint256 _sysEth = bonds[_id].deposit.mul(issuerFee).div(divider);
        systemETH = systemETH.add(_sysEth);

        uint256 _tmv = bonds[_id].deposit.mul(rate()).div(precision());
        uint256 _box = ITBoxManager(settings.tBoxManager()).create.value(msg.value)(_tmv);

        bonds[_id].issuer = msg.sender;
        bonds[_id].tmv = _tmv;
        bonds[_id].expiration = bonds[_id].expiration.add(now);
        bonds[_id].sysFee = holderFee;
        bonds[_id].tBoxId = _box;
        bonds[_id].createdAt = now;

        msg.sender.transfer(bonds[_id].deposit.sub(_sysEth));
        IToken(settings.tmvAddress()).transfer(_holder, _tmv);
        emit BondMatched(_id, msg.sender, _box, _tmv, holderFee, _holder);
    }

    /// @dev Finishes the bond.
    /// @param _id A Bond ID.
    function finish(uint256 _id) external onlyIssuer(_id) validTx {

        Bond memory bond = bonds[_id];

        // It's not necessary to check matching of the bond
        // since the expiration period cannot exceed 365 days.
        require(now < bond.expiration, "Bond expired");

        uint256 _secondsPast = now.sub(bond.createdAt);
        (uint256 _eth, ) = getBox(bond.tBoxId);

        uint256 _yearFee = bond.tmv
            .mul(_secondsPast)
            .mul(bond.yearFee)
            .div(365 days)
            .div(divider);
        uint256 _sysTMV = _yearFee.mul(bond.sysFee).div(divider);

        address _holder = bond.holder;

        if (_sysTMV > 0) {
            IToken(settings.tmvAddress()).transferFrom(
                msg.sender,
                address(this),
                _sysTMV
            );
        }
        if (_yearFee > 0) {
            IToken(settings.tmvAddress()).transferFrom(
                msg.sender,
                _holder,
                _yearFee.sub(_sysTMV)
            );
        }

        if (_eth > 0) {
            ITBoxManager(settings.tBoxManager()).transferFrom(address(this), msg.sender, bond.tBoxId);
        }
        // when TBox no longer exists
        delete bonds[_id];

        emit BondFinished(_id, msg.sender, _holder);
    }

    /// @dev Executes expiration process of the bond.
    /// @param _id A Bond ID.
    function expire(uint256 _id) external matched(_id) validTx {
        require(now > bonds[_id].expiration, "Bond hasn't expired");

        (uint256 _eth, uint256 _tmv) = getBox(bonds[_id].tBoxId);

        if (_eth == 0) {
            emit BondExpired(_id, bonds[_id].issuer, bonds[_id].holder);
            delete bonds[_id];
            return;
        }

        uint256 _collateralPercent = ITBoxManager(settings.tBoxManager()).collateralPercent(bonds[_id].tBoxId);
        uint256 _targetCollateralPercent = settings.globalTargetCollateralization();
        if (_collateralPercent > _targetCollateralPercent) {
            uint256 _ethTarget = _tmv.mul(_targetCollateralPercent).div(rate()); // mul and div by precision are omitted
            uint256 _issuerEth = _eth.sub(_ethTarget);
            uint256 _withdrawableEth = ITBoxManager(settings.tBoxManager()).withdrawableEth(
                bonds[_id].tBoxId
            );
            if (_issuerEth > _withdrawableEth) {
                _issuerEth = _withdrawableEth;
            }
            ITBoxManager(settings.tBoxManager()).withdrawEth(
                bonds[_id].tBoxId,
                _issuerEth
            );
            bonds[_id].issuer.transfer(_issuerEth);
        }

        _eth = ITBoxManager(settings.tBoxManager()).withdrawableEth(
            bonds[_id].tBoxId
        );

        uint256 _commission = _eth.mul(bonds[_id].sysFee).div(divider);

        if (_commission > 0) {
            ITBoxManager(settings.tBoxManager()).withdrawEth(
                bonds[_id].tBoxId,
                _commission
            );
            systemETH = systemETH.add(_commission);
        }

        ITBoxManager(settings.tBoxManager()).transferFrom(
            address(this),
            bonds[_id].holder,
            bonds[_id].tBoxId
        );

        emit BondExpired(_id, bonds[_id].issuer, bonds[_id].holder);

        delete bonds[_id];
    }

    /// @dev Returns TBox parameters.
    /// @param _id A Bond ID.
    function getBox(uint256 _id) public view returns(uint256, uint256) {
        return ITBoxManager(settings.tBoxManager()).boxes(_id);
    }

    /// @dev Needs to claim funds from the logic contract to execute finishing and expiration.
    function() external payable {}

    /// @dev Withdraws system fee.
    /// @param _beneficiary The address to forward funds to.
    function withdrawSystemETH(address _beneficiary) external onlyAdmin {
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

    /// @dev Sets issuer fee.
    /// @param _value Commission percentage.
    function setIssuerFee(uint256 _value) external onlyAdmin {
        require(_value <= 10000, "Too much");
        issuerFee = _value;
        emit BondIssuerFeeUpdated(_value);
    }

    /// @dev Sets holder fee.
    /// @param _value Commission percentage.
    function setHolderFee(uint256 _value) external onlyAdmin {
        require(_value <= 50000, "Too much");
        holderFee = _value;
        emit BondHolderFeeUpdated(_value);
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
        return ITBoxManager(settings.tBoxManager()).precision();
    }

    /// @dev Returns current oracle ETH/USD price with precision.
    function rate() public view returns(uint256) {
        return IOracle(settings.oracleAddress()).ethUsdPrice();
    }

    /// @dev Transfers issuer's rights of an Order.
    function transferIssuerRights(address _to, uint256 _id) external onlyIssuer(_id) {
        require(_to != address(0), "Zero address, be careful");
        bonds[_id].issuer = _to;
        emit IssuerRightsTransferred(msg.sender, _to, _id);
    }

    /// @dev Transfers holder's rights of an Order.
    function transferHolderRights(address _to, uint256 _id) external onlyHolder(_id) {
        require(_to != address(0), "Zero address, be careful");
        bonds[_id].holder = _to;
        emit HolderRightsTransferred(msg.sender, _to, _id);
    }
}
