pragma solidity ^0.4.24;

import "./XRT.sol";

contract RobotLiabilityABI {
    function ask(
        bytes   _model,
        bytes   _objective,

        ERC20   _token,
        uint256 _cost,

        address _validator,
        uint256 _validator_fee,

        uint256 _deadline,
        bytes32 _nonce,
        bytes   _signature
    ) external returns (bool);

    function bid(
        bytes   _model,
        bytes   _objective,
        
        ERC20   _token,
        uint256 _cost,

        uint256 _lighthouse_fee,

        uint256 _deadline,
        bytes32 _nonce,
        bytes   _signature
    ) external returns (bool);

    function finalize(
        bytes _result,
        bytes _signature,
        bool  _agree
    ) external returns (bool);
}
