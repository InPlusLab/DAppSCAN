// SPDX-License-Identifier: MIT

pragma solidity 0.8.3;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./interfaces/ICrossroadCallee.sol";
import "./interfaces/ITokenAutoBuyer.sol";
import "./interfaces/IWETH.sol";

import "./utils/TransferHelper.sol";

contract Crossroad
{
    using SafeERC20 for IERC20;
    using Address for address;

    /* ======== DATA STRUCTURES ======== */

    enum OrderStatus
    {
        INVALID,
        OPEN,
        CANCELLED,
        FILLED
    }

    // to denote BNB, a value of 0x0 will be used for tokenIn and tokenOut
    struct Order
    {
        address poster;
        address tokenIn;
        address tokenOut;
        address tokenReward;
        uint256 amountIn;
        uint256 amountOut;
        uint256 expiryTime;
        bool deposit;
    }

    struct OrderState
    {
        OrderStatus status;
        uint256 remainingIn;
        uint256 remainingOut;
        uint256 remainingReward;
    }

    /* ======== CONSTANT VARIABLES ======== */

    // unit
    uint256 constant UNIT_ONE = 1e18;

    // tokens
    address public constant wbnbToken = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;

    /* ======== STATE VARIABLES ======== */

    // governance
    address public operator;

    // orders
    uint256 public orderCount;
    mapping(uint256 => Order) public orders;
    mapping(uint256 => OrderState) public orderStates;

    // records
    uint256 public openOrderCount;
    mapping(uint256 => uint256) nextOpenOrderIds;
    mapping(uint256 => uint256) prevOpenOrderIds;

    mapping(address => uint256) public posterOrderCounts;
    mapping(address => mapping(uint256 => uint256)) posterNextOrderIds;
    mapping(address => mapping(uint256 => uint256)) posterPrevOrderIds;
    mapping(address => uint256) public posterOpenOrderCounts;
    mapping(address => mapping(uint256 => uint256)) posterNextOpenOrderIds;
    mapping(address => mapping(uint256 => uint256)) posterPrevOpenOrderIds;

    // fees
    address public projectAddress = address(0x74031C7504499FD54b42f8e3E90061E5c01C5668);
    address public feeToken = address(0x24eacCa1086F2904962a32732590F27Ca45D1d99);
    address public feeAutoBuyer = address(0xd155Ff0EBf2064B7F6BCb0cEC7AD4C89E8a38737);
    uint256 public feeAmount = 500e14;

    // the minimum reward required to activate the auto fill feature
    // this value is purely used communicate to the UI and other potential contracts
    // if this value increases, previously submitted transactions which were activated will persist
    uint256 public autoFillReward = 500e14;

    constructor(
        address _projectAddress,
        address _feeToken,
        address _feeAutoBuyer
        )
    {
        operator = msg.sender;

        projectAddress = _projectAddress;
        feeToken = _feeToken;
        feeAutoBuyer = _feeAutoBuyer;
    }

    /* ======== EVENTS ======== */

    event OrderPlaced(uint256 indexed orderId, address indexed tokenIn, address indexed tokenOut);
    event OrderRenewed(uint256 indexed orderId);
    event OrderCancelled(uint256 indexed orderId);
    event OrderFilledPartial(uint256 indexed orderId);
    event OrderFilledComplete(uint256 indexed orderId);

    /* ======== MODIFIER ======== */

    modifier onlyOperator()
    {
        require(operator == msg.sender, "Crossroad: Caller is not the operator");
        _;
    }

    /* ======== FALLBACK FUNCTIONS ======== */

    receive() external payable {
    }

    /* ======== PUBLIC VIEW FUNCTIONS ======== */

    // orders
    function orderPoster(
        uint256 _orderId
        ) public view
        returns (address)
    {
        return orders[_orderId].poster;
    }

    function orderTokenIn(
        uint256 _orderId
        ) public view
        returns (address)
    {
        return orders[_orderId].tokenIn;
    }

    function orderTokenOut(
        uint256 _orderId
        ) public view
        returns (address)
    {
        return orders[_orderId].tokenOut;
    }

    function orderTokenReward(
        uint256 _orderId
        ) public view
        returns (address)
    {
        return orders[_orderId].tokenReward;
    }

    function orderAmountIn(
        uint256 _orderId
        ) public view
        returns (uint256)
    {
        return orders[_orderId].amountIn;
    }

    function orderAmountOut(
        uint256 _orderId
        ) public view
        returns (uint256)
    {
        return orders[_orderId].amountOut;
    }

    function orderExpiryTime(
        uint256 _orderId
        ) public view
        returns (uint256)
    {
        return orders[_orderId].expiryTime;
    }

    function orderDeposit(
        uint256 _orderId
        ) public view
        returns (bool)
    {
        return orders[_orderId].deposit;
    }

    // order states
    function orderStatus(
        uint256 _orderId
        ) public view
        returns (OrderStatus)
    {
        return orderStates[_orderId].status;
    }

    function orderRemainingIn(
        uint256 _orderId
        ) external view
        returns (uint256)
    {
        return orderStates[_orderId].remainingIn;
    }

    function orderRemainingOut(
        uint256 _orderId
        ) external view
        returns (uint256)
    {
        return orderStates[_orderId].remainingOut;
    }

    function orderRemainingReward(
        uint256 _orderId
        ) external view
        returns (uint256)
    {
        return orderStates[_orderId].remainingReward;
    }

    function orderCanBeFilled(
        uint256 _orderId
        ) public view
        returns (bool)
    {
        return
            block.timestamp < orders[_orderId].expiryTime &&
            orderStates[_orderId].status == OrderStatus.OPEN
            ;
    }

    function orderCanBeFilledCompleteCheckAllowanceAndBalance(
        uint256 _orderId
        ) external view
        returns (bool)
    {
        Order storage order = orders[_orderId];
        OrderState storage state = orderStates[_orderId];
        if (!orderCanBeFilled(_orderId)) return false;
        if (order.deposit) return true;

        return
            state.remainingIn < IERC20(order.tokenIn).balanceOf(order.poster) &&
            state.remainingIn < IERC20(order.tokenIn).allowance(order.poster,address(this))
            ;
    }

    function orderRemainingInCheckAllowanceAndBalance(
        uint256 _orderId
        ) external view
        returns (uint256)
    {
        Order storage order = orders[_orderId];
        OrderState storage state = orderStates[_orderId];
        if (!orderCanBeFilled(_orderId)) return 0;
        if (order.deposit) return state.remainingIn;

        return Math.min(
            state.remainingIn,
            Math.min(
                IERC20(order.tokenIn).balanceOf(order.poster),
                IERC20(order.tokenIn).allowance(order.poster,address(this))
                )
            );
    }

    function orderAmountInFromAmountOut(
        uint256 _orderId,
        uint256 _amountOut
        ) external view
        returns (uint256)
    {
        OrderState storage state = orderStates[_orderId];
        if (!orderCanBeFilled(_orderId)) return 0;
        if (state.remainingOut <= _amountOut) return state.remainingIn;

        return (state.remainingIn * _amountOut) / state.remainingOut;
    }

    function orderAmountRewardFromAmountOut(
        uint256 _orderId,
        uint256 _amountOut
        ) external view
        returns (uint256)
    {
        OrderState storage state = orderStates[_orderId];
        if (!orderCanBeFilled(_orderId)) return 0;
        if (state.remainingOut <= _amountOut) return state.remainingReward;

        return (state.remainingReward * _amountOut) / state.remainingOut;
    }

    // records
    function allOpenOrders(
        ) external view
        returns (uint256[] memory)
    {
        uint256[] memory _openOrderIds = new uint256[](openOrderCount);
        uint256 _index = 0;
        for (
            uint256 _currOpenOrderId = nextOpenOrderIds[0];
            _currOpenOrderId != 0;
            _currOpenOrderId = nextOpenOrderIds[_currOpenOrderId]
            )
        {
            _openOrderIds[_index] = _currOpenOrderId;
            _index += 1;
        }
        return _openOrderIds;
    }

    function posterOrders(
        address _poster
        ) external view
        returns (uint256[] memory)
    {
        mapping(uint256 => uint256) storage _nextOrderIds = posterNextOrderIds[_poster];

        uint256[] memory _openIds = new uint256[](posterOrderCounts[_poster]);
        uint256 _index = 0;
        for (
            uint256 _currOrderId = _nextOrderIds[0];
            _currOrderId != 0;
            _currOrderId = _nextOrderIds[_currOrderId]
            )
        {
            _openIds[_index] = _currOrderId;
            _index += 1;
        }
        return _openIds;
    }

    function posterOpenOrders(
        address _poster
        ) external view
        returns (uint256[] memory)
    {
        mapping(uint256 => uint256) storage _nextOpenOrderIds = posterNextOpenOrderIds[_poster];

        uint256[] memory _openOrderIds = new uint256[](posterOpenOrderCounts[_poster]);
        uint256 _index = 0;
        for (
            uint256 _currOpenOrderId = _nextOpenOrderIds[0];
            _currOpenOrderId != 0;
            _currOpenOrderId = _nextOpenOrderIds[_currOpenOrderId]
            )
        {
            _openOrderIds[_index] = _currOpenOrderId;
            _index += 1;
        }
        return _openOrderIds;
    }

    /* ======== USER FUNCTIONS ======== */

    function postOrderPayFee(
        address _tokenIn,
        address _tokenOut,
        uint256 _amountIn,
        uint256 _amountOut,
        uint256 _expiryTime,
        bool _deposit,
        uint256 _rewardAmount
        ) external returns (uint256 orderId_)
    {
        require(_tokenIn != address(0), "Crossroad: Wrong function call");
        require(_tokenIn != _tokenOut, "Crossroad: Cannot trade a token for itself");
        require(0 < _amountIn, "Crossroad: Cannot trade nothing");
        require(0 < _amountOut, "Crossroad: Cannot trade nothing");

        depositTokenIn(_tokenIn,_amountIn,_deposit);
        payFee(_rewardAmount);

        orderId_ = createOrder(
            _tokenIn,
            _tokenOut,
            _amountIn,
            _amountOut,
            _expiryTime,
            _deposit,
            _rewardAmount
            );
    }

    function postOrderBuyFee(
        address _tokenIn,
        address _tokenOut,
        uint256 _amountIn,
        uint256 _amountOut,
        uint256 _expiryTime,
        bool _deposit,
        uint256 _rewardAmount
        ) external payable returns (uint256 orderId_)
    {
        require(_tokenIn != address(0), "Crossroad: Wrong function call");
        require(_tokenIn != _tokenOut, "Crossroad: Cannot trade a token for itself");
        require(0 < _amountIn, "Crossroad: Cannot trade nothing");
        require(0 < _amountOut, "Crossroad: Cannot trade nothing");

        depositTokenIn(_tokenIn,_amountIn,_deposit);
        buyFee(msg.value,_rewardAmount);

        orderId_ = createOrder(
            _tokenIn,
            _tokenOut,
            _amountIn,
            _amountOut,
            _expiryTime,
            _deposit,
            _rewardAmount
            );
    }

    function postOrderInBnbPayFee(
        address _tokenOut,
        uint256 _amountOut,
        uint256 _expiryTime,
        uint256 _rewardAmount
        ) external payable returns (uint256 orderId_)
    {
        require(address(0) != _tokenOut, "Crossroad: Cannot trade a token for itself");
        require(0 < msg.value, "Crossroad: Cannot trade nothing");
        require(0 < _amountOut, "Crossroad: Cannot trade nothing");

        payFee(_rewardAmount);

        orderId_ = createOrder(
            address(0),
            _tokenOut,
            msg.value,
            _amountOut,
            _expiryTime,
            true, // bnb transactions must be deposited
            _rewardAmount
            );
    }

    function postOrderInBnbBuyFee(
        address _tokenOut,
        uint256 _amountIn,
        uint256 _amountOut,
        uint256 _expiryTime,
        uint256 _rewardAmount
        ) external payable returns (uint256 orderId_)
    {
        require(address(0) != _tokenOut, "Crossroad: Cannot trade a token for itself");
        require(0 < _amountIn, "Crossroad: Cannot trade nothing");
        require(0 < _amountOut, "Crossroad: Cannot trade nothing");

        uint256 _feeBnbAmount = msg.value - _amountIn;
        buyFee(_feeBnbAmount,_rewardAmount);

        orderId_ = createOrder(
            address(0),
            _tokenOut,
            _amountIn,
            _amountOut,
            _expiryTime,
            true, // bnb transactions must be deposited
            _rewardAmount
            );
    }

    function renewOrder(
        uint256 _orderId,
        uint256 _expiryTime
        ) external
    {
        Order storage order = orders[_orderId];
        OrderState storage state = orderStates[_orderId];

        require(order.poster == msg.sender, "Crossroad: Can't renew another poster's order");
        require(state.status == OrderStatus.OPEN, "Crossroad: Order is not open");

        emit OrderRenewed(_orderId);

        order.expiryTime = _expiryTime;
    }

    function cancelOrder(
        uint256 _orderId
        ) external
    {
        require(_orderId != 0 && _orderId <= orderCount, "Crossroad: Invalid order");

        Order storage order = orders[_orderId];
        OrderState storage state = orderStates[_orderId];

        require(order.poster == msg.sender, "Crossroad: Can't cancel another poster's order");
        require(state.status == OrderStatus.OPEN, "Crossroad: Order is not open");

        // mark as cancelled
        state.status = OrderStatus.CANCELLED;
        // remove from record keeping
        recordCloseOrder(order.poster, _orderId);

        emit OrderCancelled(_orderId);

        // update amounts
        uint256 _amountIn = state.remainingIn;
        uint256 _amountReward = state.remainingReward;

        state.remainingIn = 0;
        state.remainingOut = 0;
        state.remainingReward = 0;

        // refund any remaining deposit
        if (order.deposit)
        {
            if (order.tokenIn == address(0))
            {
                TransferHelper.safeTransferETH(order.poster,_amountIn);
            }
            else
            {
                IERC20(order.tokenIn).safeTransfer(order.poster,_amountIn);
            }
        }

        // refund any remaining reward
        IERC20(order.tokenReward).safeTransfer(order.poster,_amountReward);
    }

    function fillOrderOutToken(
        uint256 _orderId,
        uint256 _amountOut,
        address _to,
        bool _callback,
        bytes calldata _callbackData
        ) external
    {
        require(_orderId != 0 && _orderId <= orderCount, "Crossroad: Invalid order");

        Order storage order = orders[_orderId];
        OrderState storage state = orderStates[_orderId];

        require(address(0) != order.tokenOut, "Crossroad: Wrong function call");

        uint256 _amountIn;
        uint256 _amountReward;
        (_amountIn,_amountOut,_amountReward) = processFillOrder(_orderId,order,state,_amountOut);

        // transfer token in to caller
        transferTokenInToCaller(_orderId,_amountIn,_to);

        // transfer reward to caller
        IERC20(order.tokenReward).safeTransfer(_to,_amountReward);

        // crossroad callback
        if (_callback)
        {
            ICrossroadCallee(_to).crossroadCall(
                msg.sender,
                _amountIn,
                _amountOut,
                _amountReward,
                _callbackData
                );
        }

        // transfer token out to poster
        IERC20(order.tokenOut).safeTransferFrom(_to,order.poster,_amountOut);
    }

    function fillOrderOutBnb(
        uint256 _orderId,
        uint256 _amountOut,
        address _to,
        bool _callback,
        bytes calldata _callbackData
        ) external payable
    {
        require(_orderId != 0 && _orderId <= orderCount, "Crossroad: Invalid order");

        Order storage order = orders[_orderId];
        OrderState storage state = orderStates[_orderId];

        require(address(0) == order.tokenOut, "Crossroad: Wrong function call");

        uint256 _amountIn;
        uint256 _amountReward;
        (_amountIn,_amountOut,_amountReward) = processFillOrder(_orderId,order,state,_amountOut);

        // transfer token in to caller
        transferTokenInToCaller(_orderId,_amountIn,_to);

        // transfer reward to caller
        IERC20(order.tokenReward).safeTransfer(_to,_amountReward);

        // crossroad callback
        uint256 _totalValue = msg.value;
        if (_callback)
        {
            uint256 _prevBalanceBnb = address(this).balance;
            ICrossroadCallee(_to).crossroadCall(
                msg.sender,
                _amountIn,
                _amountOut,
                _amountReward,
                _callbackData
                );
            uint256 _currBalanceBnb = address(this).balance;

            _totalValue += _currBalanceBnb - _prevBalanceBnb;
        }
        require(_amountOut <= _totalValue, "Crossroad: Insufficient BNB paid");

        // refund excess BNB
        TransferHelper.safeTransferETH(msg.sender,_totalValue-_amountOut);

        // transfer token out to poster
        TransferHelper.safeTransferETH(order.poster,_amountOut);
    }

    /* ======== OPERATOR FUNCTIONS ======== */

    function setProjectAddress(
        address _projectAddress
        ) external onlyOperator
    {
        projectAddress = _projectAddress;
    }

    function setFeeToken(
        address _feeToken,
        address _feeAutoBuyer
        ) external onlyOperator
    {
        feeToken = _feeToken;
        feeAutoBuyer = _feeAutoBuyer;
    }

    function setFeeAmount(
        uint256 _feeAmount
        ) external onlyOperator
    {
        feeAmount = _feeAmount;
    }

    /* ======== INTERNAL VIEW FUNCTIONS ======== */

    /* ======== INTERNAL FUNCTIONS ======== */

    function depositTokenIn(
        address _tokenIn,
        uint256 _amountIn,
        bool _deposit
        ) internal
    {
        if (_deposit)
        {
            // transfer tokens
            // check for transfer fees
            uint256 _prevBalance = IERC20(_tokenIn).balanceOf(address(this));
            IERC20(_tokenIn).safeTransferFrom(msg.sender,address(this),_amountIn);
            uint256 _currBalance = IERC20(_tokenIn).balanceOf(address(this));
            require(_prevBalance + _amountIn == _currBalance, "Crossroad: Transfer fee detected");
        }
    }

    function payFee(
        uint256 _rewardAmount
        ) internal
    {
        IERC20(feeToken).safeTransferFrom(msg.sender,projectAddress,feeAmount);
        IERC20(feeToken).safeTransferFrom(msg.sender,address(this),_rewardAmount);
    }

    function buyFee(
        uint256 _bnbAmount,
        uint256 _rewardAmount
        ) internal
    {
        uint256 _prevRewardBalance = IERC20(feeToken).balanceOf(address(this));

        // buy fee and reward
        // transfer fee to project
        uint256 _feeAndRewardAmount = feeAmount + _rewardAmount;
        ITokenAutoBuyer(feeAutoBuyer).buyTokenFixed{value: _bnbAmount}(_feeAndRewardAmount,address(this),msg.sender);
        IERC20(feeToken).safeTransfer(projectAddress,feeAmount);

        require(_prevRewardBalance + _rewardAmount <= IERC20(feeToken).balanceOf(address(this)), "Crossroad: Fee auto buyer error");
    }

    function createOrder(
        address _tokenIn,
        address _tokenOut,
        uint256 _amountIn,
        uint256 _amountOut,
        uint256 _expiryTime,
        bool _deposit,
        uint256 _rewardAmount
        ) internal returns (uint256 orderId_)
    {
        // add order
        orderCount += 1;
        orderId_ = orderCount;

        orders[orderId_] = Order(
        {
            poster: msg.sender,
            tokenIn: _tokenIn,
            tokenOut: _tokenOut,
            tokenReward: feeToken,
            amountIn: _amountIn,
            amountOut: _amountOut,
            expiryTime: _expiryTime,
            deposit: _deposit
        });

        orderStates[orderId_] = OrderState(
        {
            status: OrderStatus.OPEN,
            remainingIn: _amountIn,
            remainingOut: _amountOut,
            remainingReward: _rewardAmount
        });

        // add to record keeping
        recordOpenOrder(msg.sender, orderId_);

        emit OrderPlaced(orderId_, _tokenIn, _tokenOut);
        return orderId_;
    }

    function transferTokenInToCaller(
        uint256 _orderId,
        uint256 _amountIn,
        address _to
        ) internal
    {
        Order storage _order = orders[_orderId];

        if (_order.deposit)
        {
            if (_order.tokenIn == address(0))
            {
                TransferHelper.safeTransferETH(_to,_amountIn);
            }
            else
            {
                IERC20(_order.tokenIn).safeTransfer(_to,_amountIn);
            }
        }
        else
        {
            IERC20(_order.tokenIn).safeTransferFrom(_order.poster,_to,_amountIn);
        }
    }

    function processFillOrder(
        uint256 _orderId,
        Order storage order,
        OrderState storage state,
        uint256 _amountOut
        ) internal returns (uint256 amountIn_, uint256 amountOut_, uint256 amountReward_)
    {
        require(0 < _amountOut, "Crossroad: Cannot trade nothing");
        require(state.status == OrderStatus.OPEN, "Crossroad: Order is not open");
        require(block.timestamp < order.expiryTime, "Crossroad: Order has expired");

        amountOut_ = Math.min(_amountOut, state.remainingOut);

        if (amountOut_ == state.remainingOut)
        {
            // mark as filled
            state.status = OrderStatus.FILLED;
            // remove from record keeping
            recordCloseOrder(order.poster, _orderId);

            emit OrderFilledComplete(_orderId);

            // update amounts
            amountIn_ = state.remainingIn;
            amountReward_ = state.remainingReward;

            state.remainingIn = 0;
            state.remainingOut = 0;
            state.remainingReward = 0;
        }
        else
        {
            emit OrderFilledPartial(_orderId);

            // update amounts
            amountIn_ = (state.remainingIn * amountOut_) / state.remainingOut;
            amountReward_ = (state.remainingReward * amountOut_) / state.remainingOut;

            state.remainingIn -= amountIn_;
            state.remainingOut -= amountOut_;
            state.remainingReward -= amountReward_;
        }
    }

    // record keeping
    function recordOpenOrder(
        address _poster,
        uint256 _orderId
        ) internal
    {
        // update global orders
        {
            openOrderCount += 1;

            uint256 _prevNewestOpenOrderId = prevOpenOrderIds[0];

            nextOpenOrderIds[_prevNewestOpenOrderId] = _orderId;
            prevOpenOrderIds[_orderId] = _prevNewestOpenOrderId;

            prevOpenOrderIds[0] = _orderId;
        }

        // update poster orders
        {
            posterOrderCounts[_poster] += 1;
            posterOpenOrderCounts[_poster] += 1;

            {
                uint256 _prevPosterNewestOrderId = posterPrevOrderIds[_poster][0];

                posterNextOrderIds[_poster][_prevPosterNewestOrderId] = _orderId;
                posterPrevOrderIds[_poster][_orderId] = _prevPosterNewestOrderId;

                posterPrevOrderIds[_poster][0] = _orderId;
            }

            {
                uint256 _prevPosterNewestOpenOrderId = posterPrevOpenOrderIds[_poster][0];

                posterNextOpenOrderIds[_poster][_prevPosterNewestOpenOrderId] = _orderId;
                posterPrevOpenOrderIds[_poster][_orderId] = _prevPosterNewestOpenOrderId;

                posterPrevOpenOrderIds[_poster][0] = _orderId;
            }
        }
    }

    function recordCloseOrder(
        address _poster,
        uint256 _orderId
        ) internal
    {
        // update global orders
        {
            openOrderCount -= 1;

            uint256 _nextOpenOrderId = nextOpenOrderIds[_orderId];
            uint256 _prevOpenOrderId = prevOpenOrderIds[_orderId];

            nextOpenOrderIds[_prevOpenOrderId] = _nextOpenOrderId;
            prevOpenOrderIds[_nextOpenOrderId] = _prevOpenOrderId;
        }

        // update poster orders
        {
            posterOpenOrderCounts[_poster] -= 1;

            mapping(uint256 => uint256) storage _nextOpenOrderIds = posterNextOpenOrderIds[_poster];
            mapping(uint256 => uint256) storage _prevOpenOrderIds = posterPrevOpenOrderIds[_poster];

            uint256 _nextOpenOrderId = _nextOpenOrderIds[_orderId];
            uint256 _prevOpenOrderId = _prevOpenOrderIds[_orderId];

            _nextOpenOrderIds[_prevOpenOrderId] = _nextOpenOrderId;
            _prevOpenOrderIds[_nextOpenOrderId] = _prevOpenOrderId;
        }
    }
}
