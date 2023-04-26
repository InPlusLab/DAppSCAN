// "SPDX-License-Identifier: GPL-3.0-or-later"

pragma solidity 0.7.6;

import "../libs/BokkyPooBahsDateTimeLibrary/BokkyPooBahsDateTimeLibrary.sol";

contract TokenMetadataGenerator {
    function formatDate(uint256 _posixDate)
        internal
        view
        returns (string memory)
    {
        uint256 year;
        uint256 month;
        uint256 day;
        (year, month, day) = BokkyPooBahsDateTimeLibrary.timestampToDate(
            _posixDate
        );

        return
            concat(
                uint2str(day),
                concat(
                    getMonthShortName(month),
                    uint2str(getCenturyYears(year))
                )
            );
    }

    function formatMeta(
        string memory _prefix,
        string memory _concatenator,
        string memory _date,
        string memory _postfix
    ) internal pure returns (string memory) {
        return concat(_prefix, concat(_concatenator, concat(_date, _postfix)));
    }

    function makeTokenName(
        string memory _baseName,
        string memory _date,
        string memory _postfix
    ) internal pure returns (string memory) {
        return formatMeta(_baseName, " ", _date, _postfix);
    }

    function makeTokenSymbol(
        string memory _baseName,
        string memory _date,
        string memory _postfix
    ) internal pure returns (string memory) {
        return formatMeta(_baseName, "-", _date, _postfix);
    }

    function getCenturyYears(uint256 _year) internal pure returns (uint256) {
        return _year % 100;
    }

    function concat(string memory _a, string memory _b)
        internal
        pure
        returns (string memory)
    {
        return string(abi.encodePacked(bytes(_a), bytes(_b)));
    }

    function uint2str(uint256 _i)
        internal
        pure
        returns (string memory _uintAsString)
    {
        if (_i == 0) {
            return "0";
        }
        uint256 j = _i;
        uint256 len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint256 k = len - 1;
        while (_i != 0) {
            bstr[k--] = bytes1(uint8(48 + (_i % 10)));
            _i /= 10;
        }
        return string(bstr);
    }

    function getMonthShortName(uint256 _month)
        internal
        pure
        returns (string memory)
    {
        if (_month == 1) {
            return "Jan";
        }
        if (_month == 2) {
            return "Feb";
        }
        if (_month == 3) {
            return "Mar";
        }
        if (_month == 4) {
            return "Apr";
        }
        if (_month == 5) {
            return "May";
        }
        if (_month == 6) {
            return "Jun";
        }
        if (_month == 7) {
            return "Jul";
        }
        if (_month == 8) {
            return "Aug";
        }
        if (_month == 9) {
            return "Sep";
        }
        if (_month == 10) {
            return "Oct";
        }
        if (_month == 11) {
            return "Nov";
        }
        if (_month == 12) {
            return "Dec";
        }
        return "NaN";
    }
}
