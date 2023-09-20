pragma solidity ^0.4.24;

import 'openzeppelin-solidity/contracts/ECRecovery.sol';
import './RobotLiabilityABI.sol';
import './RobotLiabilityAPI.sol';

contract RobotLiabilityLib is RobotLiabilityABI
                            , RobotLiabilityAPI {
    using ECRecovery for bytes32;

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
    )
        external
        returns (bool)
    {
        require(msg.sender == address(factory));
        require(block.number < _deadline);

        model        = _model;
        objective    = _objective;
        token        = _token;
        cost         = _cost;
        validator    = _validator;
        validatorFee = _validator_fee;

        askHash = keccak256(abi.encodePacked(
            _model
          , _objective
          , _token
          , _cost
          , _validator
          , _validator_fee
          , _deadline
          , _nonce
        ));

        promisee = askHash
            .toEthSignedMessageHash()
            .recover(_signature);
        return true;
    }

    function bid(
        bytes   _model,
        bytes   _objective,
        
        ERC20   _token,
        uint256 _cost,

        uint256 _lighthouse_fee,

        uint256 _deadline,
        bytes32 _nonce,
        bytes   _signature
    )
        external
        returns (bool)
    {
        require(msg.sender == address(factory));
        require(block.number < _deadline);
        //SWC-133-Hash Collisions With Multiple Variable Length Arguments: L74-L75
        require(keccak256(abi.encodePacked(model, objective))
                == keccak256(abi.encodePacked(_model, _objective)));
        require(_token == token);
        require(_cost == cost);

        lighthouseFee = _lighthouse_fee;

        bidHash = keccak256(abi.encodePacked(
            _model
          , _objective
          , _token
          , _cost
          , _lighthouse_fee
          , _deadline
          , _nonce
        ));

        promisor = bidHash
            .toEthSignedMessageHash()
            .recover(_signature);
        return true;
    }

    /**
     * @dev Finalize this liability
     * @param _result Result data hash
     * @param _agree Validation network confirmation
     * @param _signature Result sender signature
     */
     //SWC-107-Reentrancy: L104
    function finalize(
        bytes _result,
        bytes _signature,
        bool  _agree
    )
        external
        returns (bool)
    {
        uint256 gasinit = gasleft();
        require(!isFinalized);

        address resultSender = keccak256(abi.encodePacked(this, _result))
            .toEthSignedMessageHash()
            .recover(_signature);
        require(resultSender == promisor);

        if (validator == 0) {
            require(factory.isLighthouse(msg.sender));
            require(token.transfer(promisor, cost));
        } else {
            require(msg.sender == validator);

            isConfirmed = _agree;
            if (isConfirmed)
                require(token.transfer(promisor, cost));
            else
                require(token.transfer(promisee, cost));

            if (validatorFee > 0)
                require(factory.xrt().transfer(validator, validatorFee));
        }

        result = _result;
        isFinalized = true;

        require(factory.liabilityFinalized(gasinit));
        return true;
    }
}
