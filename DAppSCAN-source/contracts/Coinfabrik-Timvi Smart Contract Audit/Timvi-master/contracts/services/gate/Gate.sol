pragma solidity 0.4.25;

import "../../helpers/SafeMath.sol";
import "../../helpers/ISettings.sol";
import "../../helpers/IToken.sol";
import "../../helpers/IOracle.sol";
import "../../helpers/ITBoxManager.sol";


/// @title Gate
contract Gate {
    using SafeMath for uint256;

    /// @notice The address of the admin account.
    address public admin;

    // Fee percentage for TMV exchange
    uint256 public feePercentTMV;

    // Fee percentage for ETH exchange
    uint256 public feePercentETH;

    // Minimum amount to create order in TMV (18 decimals)
    uint256 public minOrder;

    // The address to transfer tokens
    address public timviWallet;

    ISettings public settings;

    /// @dev An array containing the Order struct for all Orders in existence. The ID
    ///  of each Order is actually an index into this array.
    Order[] public orders;

    /// @dev The Order struct. Every Order is represented by a copy
    ///  of this structure.
    struct Order {
        address owner;
        uint256 amount;
    }

    /// @dev The OrderCreated event is fired whenever a new Order comes into existence.
    event OrderCreated(uint256 id, address owner, uint256 tmv);

    /// @dev The OrderCancelled event is fired whenever an Order is cancelled.
    event OrderCancelled(uint256 id, address owner, uint256 tmv);

    /// @dev The OrderFilled event is fired whenever an Order is filled.
    event OrderFilled(uint256 id, address owner, uint256 tmvTotal, uint256 tmvExecution, uint256 ethTotal, uint256 ethExecution);

    /// @dev The OrderFilledPool event is fired whenever an Order is filled.
    event OrderFilledPool(uint256 id, address owner, uint256 tmv, uint256 eth);

    /// @dev The Converted event is fired whenever an exchange is processed immediately.
    event Converted(address owner, uint256 tmv, uint256 eth);

    /// @dev The Funded event is fired whenever the contract is funded.
    event Funded(uint256 eth);

    /// @dev The AdminChanged event is fired whenever the admin is changed.
    event AdminChanged(address admin);

    event GateTmvFeeUpdated(uint256 value);
    event GateEthFeeUpdated(uint256 value);
    event GateMinOrderUpdated(uint256 value);
    event TimviWalletChanged(address wallet);
    event GateFundsWithdrawn(uint256 value);

    /// @dev Access modifier for admin-only functionality.
    modifier onlyAdmin() {
        require(admin == msg.sender, "You have no access");
        _;
    }

    /// @dev Defends against front-running attacks.
    modifier validTx() {
        require(tx.gasprice <= settings.gasPriceLimit(), "Gas price is greater than allowed");
        _;
    }

    /// @notice ISettings address can't be changed later.
    /// @dev The contract constructor sets the original `admin` of the contract to the sender
    //   account and sets the settings contract with provided address.
    /// @param _settings The address of the settings contract.
    constructor(ISettings _settings) public {
        admin = msg.sender;
        timviWallet = msg.sender;
        settings = ISettings(_settings);

        feePercentTMV = 500; // 0.5%
        feePercentETH = 500; // 0.5%
        minOrder = 10 ** 18; // 1 TMV by default

        emit GateTmvFeeUpdated(feePercentTMV);
        emit GateEthFeeUpdated(feePercentETH);
        emit GateMinOrderUpdated(minOrder);
        emit TimviWalletChanged(timviWallet);
        emit AdminChanged(admin);
    }

    function fundAdmin() external payable {
        emit Funded(msg.value);
    }

    /// @dev Withdraws ETH.
    function withdraw(address _beneficiary, uint256 _amount) external onlyAdmin {
        require(_beneficiary != address(0), "Zero address, be careful");
        require(address(this).balance >= _amount, "Insufficient funds");
        _beneficiary.transfer(_amount);
        emit GateFundsWithdrawn(_amount);
    }

    /// @dev Sets feePercentTMV.
    function setTmvFee(uint256 _value) external onlyAdmin {
        require(_value <= 10000, "Too much");
        feePercentTMV = _value;
        emit GateTmvFeeUpdated(_value);
    }

    /// @dev Sets feePercentETH.
    function setEthFee(uint256 _value) external onlyAdmin {
        require(_value <= 10000, "Too much");
        feePercentETH = _value;
        emit GateEthFeeUpdated(_value);
    }

    /// @dev Sets minimum order amount.
    function setMinOrder(uint256 _value) external onlyAdmin {
        // The "ether" word just multiplies given value by 10 ** 18
        require(_value <= 100 ether, "Too much");

        minOrder = _value;
        emit GateMinOrderUpdated(_value);
    }

    /// @dev Sets timvi wallet address.
    function setTimviWallet(address _wallet) external onlyAdmin {
        require(_wallet != address(0), "Zero address, be careful");

        timviWallet = _wallet;
        emit TimviWalletChanged(_wallet);
    }

    /// @dev Sets admin address.
    function changeAdmin(address _newAdmin) external onlyAdmin {
        require(_newAdmin != address(0), "Zero address, be careful");
        admin = _newAdmin;
        emit AdminChanged(msg.sender);
    }

    function convert(uint256 _amount) external validTx {
        require(_amount >= minOrder, "Too small amount");
        require(IToken(settings.tmvAddress()).allowance(msg.sender, address(this)) >= _amount, "Gate is not approved to transfer enough tokens");
        uint256 eth = tmv2eth(_amount);
        if (address(this).balance >= eth) {
            IToken(settings.tmvAddress()).transferFrom(msg.sender, timviWallet, _amount);
            msg.sender.transfer(eth);
            emit Converted(msg.sender, _amount, eth);
        } else {
            IToken(settings.tmvAddress()).transferFrom(msg.sender, address(this), _amount);
            uint256 id = orders.push(Order(msg.sender, _amount)).sub(1);
            emit OrderCreated(id, msg.sender, _amount);
        }
    }

    /// @dev Cancels an Order.
    function cancel(uint256 _id) external {
        require(orders[_id].owner == msg.sender, "Order isn't yours");

        uint256 tmv = orders[_id].amount;
        delete orders[_id];
        IToken(settings.tmvAddress()).transfer(msg.sender, tmv);
        emit OrderCancelled(_id, msg.sender, tmv);
    }

    /// @dev Fills Orders by ids array.
    function multiFill(uint256[] _ids) external onlyAdmin() payable {

        if (msg.value > 0) {
            emit Funded(msg.value);
        }

        for (uint256 i = 0; i < _ids.length; i++) {
            uint256 id = _ids[i];

            require(orders[id].owner != address(0), "Order doesn't exist");

            uint256 tmv = orders[id].amount;
            uint256 eth = tmv2eth(tmv);

            require(address(this).balance >= eth, "Not enough funds");

            address owner = orders[id].owner;
            if (owner.send(eth)) {
                delete orders[id];
                IToken(settings.tmvAddress()).transfer(timviWallet, tmv);
                emit OrderFilledPool(id, owner, tmv, eth);
            }
        }
    }

    /// @dev Fills an Order by id.
    function fill(uint256 _id) external payable validTx {
        require(orders[_id].owner != address(0), "Order doesn't exist");

        // Retrieve values from storage
        uint256 tmv = orders[_id].amount;
        address owner = orders[_id].owner;

        // Calculate the demand amount of Ether
        uint256 eth = tmv.mul(precision()).div(rate());

        require(msg.value >= eth, "Not enough funds");

        emit Funded(eth);

        // Calculate execution values
        uint256 tmvFee = tmv.mul(feePercentTMV).div(precision());
        uint256 ethFee = eth.mul(feePercentETH).div(precision());

        uint256 tmvExecution = tmv.sub(tmvFee);
        uint256 ethExecution = eth.sub(ethFee);

        // Remove record about an order
        delete orders[_id];

        // Transfer order' funds
        owner.transfer(ethExecution);
        IToken(settings.tmvAddress()).transfer(msg.sender, tmvExecution);
        IToken(settings.tmvAddress()).transfer(timviWallet, tmvFee);

        // Return Ether rest if exist
        msg.sender.transfer(msg.value.sub(eth));

        emit OrderFilled(_id, owner, tmv, tmvExecution, eth, ethExecution);
    }

    /// @dev Returns current oracle ETH/USD price with precision.
    function rate() public view returns(uint256) {
        return IOracle(settings.oracleAddress()).ethUsdPrice();
    }

    /// @dev Returns precision using for USD and commission calculation.
    function precision() public view returns(uint256) {
        return ITBoxManager(settings.tBoxManager()).precision();
    }

    /// @dev Calculates the ether amount to pay for a provided TMV amount.
    function tmv2eth(uint256 _amount) public view returns(uint256) {
        uint256 equivalent = _amount.mul(precision()).div(rate());
        return chargeFee(equivalent, feePercentETH);
    }

    /// @dev Reduces the amount by system fee.
    function chargeFee(uint256 _amount, uint256 _percent) public view returns(uint256) {
        uint256 fee = _amount.mul(_percent).div(precision());
        return _amount.sub(fee);
    }
}
