// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import {IIncentiveController} from './IIncentive.sol';
import {AccessControl} from '../access/AccessControl.sol';

contract IncentiveControllerRouter is AccessControl, IIncentiveController {
    /**
     * State variables.
     */

    mapping(address => IIncentiveController) public senderIncentive;
    mapping(address => IIncentiveController) public receiverIncentive;
    mapping(address => IIncentiveController) public operatorIncentive;

    /**
     * Events.
     */

    event SenderIncentive(address target, address controller);
    event ReceiverIncentive(address target, address controller);
    event OperatorIncentive(address target, address controller);

    /**
     * Modifiers.
     */
    modifier onlyAdmin() {
        require(
            hasRole(DEFAULT_ADMIN_ROLE, _msgSender()),
            'IncentiveControllerRouter: FORBIDDEN'
        );
        _;
    }

    /**
     * Constructor.
     */
    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }

    /**
     * External.
     */
    function setSenderIncentiveControllers(
        address target,
        IIncentiveController controller
    ) external onlyAdmin {
        senderIncentive[target] = controller;
        emit SenderIncentive(target, address(controller));
    }

    function setRecieverIncentiveControllers(
        address target,
        IIncentiveController controller
    ) external onlyAdmin {
        receiverIncentive[target] = controller;
        emit ReceiverIncentive(target, address(controller));
    }

    function setOperatorIncentiveControllers(
        address target,
        IIncentiveController controller
    ) external onlyAdmin {
        operatorIncentive[target] = controller;
        emit OperatorIncentive(target, address(controller));
    }

    /**
     * Public.
     */
    function incentivize(
        address sender,
        address receiver,
        address operator,
        uint256 amountIn
    ) public override {
        IIncentiveController senderIncentiveCtrl = senderIncentive[sender];
        if (address(senderIncentiveCtrl) != address(0)) {
            senderIncentiveCtrl.incentivize(
                sender,
                receiver,
                operator,
                amountIn
            );

            return;
        }

        IIncentiveController receiverIncentiveCtrl = receiverIncentive[sender];
        if (address(receiverIncentiveCtrl) != address(0)) {
            receiverIncentiveCtrl.incentivize(
                sender,
                receiver,
                operator,
                amountIn
            );

            return;
        }

        IIncentiveController operatorIncentiveCtrl = operatorIncentive[sender];
        if (address(operatorIncentiveCtrl) != address(0)) {
            IIncentiveController(operatorIncentiveCtrl).incentivize(
                sender,
                receiver,
                operator,
                amountIn
            );

            return;
        }
    }
}
