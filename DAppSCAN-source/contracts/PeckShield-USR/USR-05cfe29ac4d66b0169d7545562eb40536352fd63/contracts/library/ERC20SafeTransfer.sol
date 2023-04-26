pragma solidity 0.5.12;

import './IERC20';

contract ERC20SafeTransfer {
    function doTransferOut(address _token, address _to, uint _amount) internal returns (bool) {
        IERC20 token = IERC20(_token);
        bool _result;

        token.transfer(_to, _amount);

        assembly {
            switch returndatasize()
                case 0 {
                    _result := not(0)
                }
                case 32 {
                    returndatacopy(0, 0, 32)
                    _result := mload(0)
                }
                default {
                    revert(0, 0)
                }
        }
        return _result;
    }

    function doTransferFrom(address _token, address _from, address _to, uint _amount) internal returns (bool) {
        IERC20 token = IERC20(_token);
        bool _result;

        token.transferFrom(_from, _to, _amount);

        assembly {
            switch returndatasize()
                case 0 {
                    _result := not(0)
                }
                case 32 {
                    returndatacopy(0, 0, 32)
                    _result := mload(0)
                }
                default {
                    revert(0, 0)
                }
        }
        return _result;
    }
}
