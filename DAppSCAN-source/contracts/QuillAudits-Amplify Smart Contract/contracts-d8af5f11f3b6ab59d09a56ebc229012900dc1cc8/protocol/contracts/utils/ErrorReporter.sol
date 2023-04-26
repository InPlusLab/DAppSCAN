// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract TokenErrorReporter {
    enum Error {
        NO_ERROR,
        C_LEND_REJECTION,
        C_REDEEM_REJECTION,
        C_BORRROW_REJECTION,
        C_REPAY_REJECTION,
        C_CREATE_REJECTION,
        INSUFFICIENT_FUNDS,
        AMOUNT_LOWER_THAN_0,
        AMOUNT_HIGHER,
        AMOUNT_LOWER_THAN_MIN_DEPOSIT,
        NOT_ENOUGH_CASH,
        LOAN_HAS_DEBT,
        LOAN_IS_OVERDUE,
        LOAN_IS_NOT_CLOSED,
        LOAN_ASSET_ALREADY_USED,
        LOAN_IS_ALREADY_CLOSED,
        LOAN_PENALTY_NOT_PAYED,
        WRONG_BORROWER,
        TRANSFER_FAILED,
        LPP_TRANSFER_FAILED,
        POOL_NOT_FOUND
    }

    event Failure(uint256 error, uint256 detail);

    function fail(Error err, uint256 info) internal returns (uint256) {
        emit Failure(uint256(err), info);

        return uint256(err);
    }

    function toString(Error err) internal pure returns (string memory) {
        return ErrorReporter.uint2str(uint256(err));
    }
}

contract ControllerErrorReporter {
    enum Error {
        NO_ERROR,
        POOL_NOT_ACTIVE,
        BORROW_CAP_EXCEEDED,
        NOT_ALLOWED_TO_CREATE_CREDIT_LINE,
        BORROWER_NOT_CREATED,
        BORROWER_IS_WHITELISTED,
        BORROWER_NOT_WHITELISTED,
        ALREADY_WHITELISTED,
        INVALID_OWNER,
        MATURITY_DATE_EXPIRED,
        ASSET_REDEEMED,
        AMPT_TOKEN_TRANSFER_FAILED,
        LENDER_NOT_WHITELISTED,
        BORROWER_NOT_MEMBER,
        LENDER_NOT_CREATED
    }

    event Failure(uint256 error, uint256 detail);

    function fail(Error err) internal returns (uint256) {
        emit Failure(uint256(err), 0);

        return uint256(err);
    }

    function toString(Error err) internal pure returns (string memory) {
        return ErrorReporter.uint2str(uint256(err));
    }
}

library ErrorReporter {
    function check(uint256 err) internal pure {
        require(err == 0, uint2str(uint256(err)));
    }

    function uint2str(uint _i) internal pure returns (string memory) {
        if (_i == 0) {
            return "0";
        }
        uint j = _i;
        uint len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint k = len;
        while (_i != 0) {
            k = k-1;
            uint8 temp = (48 + uint8(_i - _i / 10 * 10));
            bytes1 b1 = bytes1(temp);
            bstr[k] = b1;
            _i /= 10;
        }
        return string(bstr);
    }
}