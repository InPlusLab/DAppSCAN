// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0;
import "@openzeppelin/contracts/access/Ownable.sol";

import "../interfaces/IBEP20.sol";
import "../libraries/SafeMath.sol";
import "../libraries/Address.sol";

/**
 * @title SafeBEP20
 * @dev Wrappers around BEP20 operations that throw on failure (when the token
 * contract returns false). Tokens that return no value (and instead revert or
 * throw on failure) are also supported, non-reverting calls are assumed to be
 * successful.
 * To use this library you can add a `using SafeBEP20 for IBEP20;` statement to your contract,
 * which allows you to call the safe operations as `token.safeTransfer(...)`, etc.
 */
library SafeBEP20 {
    using SafeMath for uint256;
    using Address for address;

    function safeTransfer(
        IBEP20 token,
        address to,
        uint256 value
    ) internal {
        _callOptionalReturn(
            token,
            abi.encodeWithSelector(token.transfer.selector, to, value)
        );
    }

    function safeTransferFrom(
        IBEP20 token,
        address from,
        address to,
        uint256 value
    ) internal {
        _callOptionalReturn(
            token,
            abi.encodeWithSelector(token.transferFrom.selector, from, to, value)
        );
    }

    /**
     * @dev Deprecated. This function has issues similar to the ones found in
     * {IBEP20-approve}, and its usage is discouraged.
     *
     * Whenever possible, use {safeIncreaseAllowance} and
     * {safeDecreaseAllowance} instead.
     */
    function safeApprove(
        IBEP20 token,
        address spender,
        uint256 value
    ) internal {
        // safeApprove should only be called when setting an initial allowance,
        // or when resetting it to zero. To increase and decrease it, use
        // 'safeIncreaseAllowance' and 'safeDecreaseAllowance'
        // solhint-disable-next-line max-line-length
        require(
            (value == 0) || (token.allowance(address(this), spender) == 0),
            "SafeBEP20: approve from non-zero to non-zero allowance"
        );
        _callOptionalReturn(
            token,
            abi.encodeWithSelector(token.approve.selector, spender, value)
        );
    }

    function safeIncreaseAllowance(
        IBEP20 token,
        address spender,
        uint256 value
    ) internal {
        uint256 newAllowance = token.allowance(address(this), spender).add(
            value
        );
        _callOptionalReturn(
            token,
            abi.encodeWithSelector(
                token.approve.selector,
                spender,
                newAllowance
            )
        );
    }

    function safeDecreaseAllowance(
        IBEP20 token,
        address spender,
        uint256 value
    ) internal {
        uint256 newAllowance = token.allowance(address(this), spender).sub(
            value,
            "SafeBEP20: decreased allowance below zero"
        );
        _callOptionalReturn(
            token,
            abi.encodeWithSelector(
                token.approve.selector,
                spender,
                newAllowance
            )
        );
    }

    /**
     * @dev Imitates a Solidity high-level call (i.e. a regular function call to a contract), relaxing the requirement
     * on the return value: the return value is optional (but if data is returned, it must not be false).
     * @param token The token targeted by the call.
     * @param data The call data (encoded using abi.encode or one of its variants).
     */
    function _callOptionalReturn(IBEP20 token, bytes memory data) private {
        // We need to perform a low level call here, to bypass Solidity's return data size checking mechanism, since
        // we're implementing it ourselves. We use {Address.functionCall} to perform this call, which verifies that
        // the target address contains contract code and also asserts for success in the low-level call.

        bytes memory returndata = address(token).functionCall(
            data,
            "SafeBEP20: low-level call failed"
        );
        if (returndata.length > 0) {
            // Return data is optional
            // solhint-disable-next-line max-line-length
            require(
                abi.decode(returndata, (bool)),
                "SafeBEP20: BEP20 operation did not succeed"
            );
        }
    }
}

contract IDO is Ownable {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;
    struct IDORecord {
        uint256 issue;
        IBEP20 idoToken;
        IBEP20 receiveToken;
        //decimals 18
        uint256 price;
        //IDO总量
        uint256 idoTotal;
        //开始时间
        uint256 startTime;
        //时长
        uint256 duration;
        uint256 maxLimit;
        //接收的总量
        uint256 receivedTotal;
        mapping(address => uint256) payAmount;
        mapping(address => bool) isWithdraw;
    }

    uint256 public IDOIssue = 0;
    mapping(uint256 => IDORecord) public IDODB;
    mapping(uint256 => bool) private isCharge;
    event IDOCreate(
        uint256 issue,
        address idoToken,
        address receiveToken,
        uint256 price,
        uint256 maxLimit,
        uint256 idoTotal,
        uint256 startTime,
        uint256 duration
    );
    event Staked(uint256 issue, address account, uint256 value);
    event Withdraw(
        uint256 issue,
        address account,
        uint256 idoValue,
        uint256 backValue
    );
    event IDOCharge(uint256 issue, uint256 receiveValue, uint256 leftValue);

    event IDORemove(uint256 issue);

    function createIDO(
        IBEP20 idoToken,
        IBEP20 receiveToken,
        uint256 price,
        uint256 idoTotal,
        uint256 maxLimit,
        uint256 startTime,
        uint256 duration
    ) external onlyOwner {
        require(
            block.timestamp >
                IDODB[IDOIssue].startTime.add(IDODB[IDOIssue].duration),
            "ido is not over yet."
        );
        require(
            address(idoToken) != address(0),
            "idoToken address cannot be 0"
        );
        require(
            address(receiveToken) != address(0),
            "receiveToken address cannot be 0"
        );

        IDOIssue = IDOIssue.add(1);
        IDORecord storage ido = IDODB[IDOIssue];
        ido.issue = IDOIssue;
        ido.idoToken = idoToken;
        ido.receiveToken = receiveToken;
        ido.price = price;
        ido.maxLimit = maxLimit;
        ido.idoTotal = idoTotal;
        ido.startTime = startTime;
        ido.duration = duration;

        idoToken.safeTransferFrom(msg.sender, address(this), idoTotal);
        emit IDOCreate(
            IDOIssue,
            address(idoToken),
            address(receiveToken),
            price,
            maxLimit,
            idoTotal,
            startTime,
            duration
        );
    }

    function removeIDO() external onlyOwner {
        require(
            IDODB[IDOIssue].startTime > block.timestamp,
            "There is no ido that can be deleted."
        );
        IDODB[IDOIssue].idoToken.safeTransfer(
            msg.sender,
            IDODB[IDOIssue].idoTotal
        );
        delete IDODB[IDOIssue];
        emit IDORemove(IDOIssue);
        IDOIssue = IDOIssue.sub(1);
    }

    function chargeIDO(uint256 issue) external onlyOwner {
        IDORecord storage record = IDODB[issue];
        require(issue <= IDOIssue && issue > 0, "IDO that does not exist.");
        require(!isCharge[issue], "Cannot claim repeatedly.");
        require(
            block.timestamp > record.startTime.add(record.duration),
            "ido is not over yet."
        );

        uint256 receiveValue;
        uint256 backValue;

        isCharge[issue] = true;

        uint256 prop = record.receivedTotal.mul(1e36).div(
            record.idoTotal.mul(record.price)
        );
        if (prop >= 1e18) {
            receiveValue = record.idoTotal.mul(record.price).div(1e18);
            record.receiveToken.safeTransfer(msg.sender, receiveValue);
        } else {
            receiveValue = record.receivedTotal;
            record.receiveToken.safeTransfer(msg.sender, record.receivedTotal);
            backValue = record.idoTotal.sub(
                record.idoTotal.mul(prop).div(1e18)
            );
            record.idoToken.safeTransfer(msg.sender, backValue);
        }

        emit IDOCharge(issue, receiveValue, backValue);
    }

    function stake(uint256 value) external {
        require(IDOIssue > 0, "IDO that does not exist.");
        IDORecord storage record = IDODB[IDOIssue];
        require(
            block.timestamp > record.startTime &&
                block.timestamp < record.startTime.add(record.duration),
            "IDO is not in progress."
        );
        require(
            record.payAmount[msg.sender].add(value) <= record.maxLimit,
            "Limit Exceeded"
        );

        record.payAmount[msg.sender] = record.payAmount[msg.sender].add(value);
        record.receivedTotal = record.receivedTotal.add(value);
        record.receiveToken.safeTransferFrom(msg.sender, address(this), value);
        emit Staked(IDOIssue, msg.sender, value);
    }

    function available(address account, uint256 issue)
        public
        view
        returns (uint256 _idoAmount, uint256 _sendBack)
    {
        IDORecord storage record = IDODB[issue];
        require(issue <= IDOIssue && issue > 0, "IDO that does not exist.");

        uint256 prop = record.receivedTotal.mul(1e36).div(
            record.idoTotal.mul(record.price)
        );

        if (prop > 1e18) {
            _idoAmount = record.payAmount[account].mul(1e36).div(prop).div(
                record.price
            );

            _sendBack = record.payAmount[account].sub(
                _idoAmount.mul(record.price).div(1e18)
            );
        } else {
            _idoAmount = record.payAmount[account].mul(1e18).div(record.price);
        }
    }

    function userPayValue(uint256 issue, address account)
        public
        view
        returns (uint256)
    {
        return IDODB[issue].payAmount[account];
    }

    function isWithdraw(uint256 issue, address account)
        public
        view
        returns (bool)
    {
        return IDODB[issue].isWithdraw[account];
    }

    function withdraw(uint256 issue) external {
        require(issue <= IDOIssue && issue > 0, "IDO that does not exist.");
        IDORecord storage record = IDODB[issue];
        require(
            block.timestamp > IDODB[issue].startTime.add(record.duration),
            "ido is not over yet."
        );
        require(!record.isWithdraw[msg.sender], "Cannot claim repeatedly.");

        uint256 idoAmount;
        uint256 sendBack;

        record.isWithdraw[msg.sender] = true;

        (idoAmount, sendBack) = available(msg.sender, issue);

        record.idoToken.safeTransfer(msg.sender, idoAmount);
        if (sendBack > 0) {
            record.receiveToken.safeTransfer(msg.sender, sendBack);
        }

        emit Withdraw(issue, msg.sender, idoAmount, sendBack);
    }
}
