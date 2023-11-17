// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.7;

import { DSTest } from "../../lib/ds-test/src/test.sol";

import { ERC20Helper } from "../ERC20Helper.sol";

import { ERC20TrueReturner, ERC20FalseReturner, ERC20NoReturner, ERC20Reverter } from "./mocks/ERC20Mocks.sol";

contract ERC20HelperTest is DSTest {
    
    ERC20FalseReturner falseReturner;
    ERC20TrueReturner  trueReturner;
    ERC20NoReturner    noReturner;
    ERC20Reverter      reverter;

    function setUp() public {
        falseReturner = new ERC20FalseReturner();
        trueReturner  = new ERC20TrueReturner();
        noReturner    = new ERC20NoReturner();
        reverter      = new ERC20Reverter();
    }

    function prove_transfer_trueReturner(address to, uint256 amount) public {
        require(ERC20Helper.transfer(address(trueReturner), to, amount));
    }

    function prove_transfer_noReturner(address to, uint256 amount) public {
        require(ERC20Helper.transfer(address(noReturner), to, amount));
    }

    function prove_transferFrom_trueReturner(address from, address to, uint256 amount) public {
        require(ERC20Helper.transferFrom(address(trueReturner), from, to, amount));
    }

    function prove_transferFrom_noReturner(address from, address to, uint256 amount) public {
        require(ERC20Helper.transferFrom(address(noReturner), from, to, amount));
    }

    function prove_approve_trueReturner(address to, uint256 amount) public {
        require(ERC20Helper.approve(address(trueReturner), to, amount));
    }

    function prove_approve_noReturner(address to, uint256 amount) public {
        require(ERC20Helper.approve(address(noReturner), to, amount));
    }

    function proveFail_transfer_falseReturner(address to, uint256 amount) public {
        require(ERC20Helper.transfer(address(falseReturner), to, amount));
    }

    function proveFail_transfer_reverter(address to, uint256 amount) public {
        require(ERC20Helper.transfer(address(reverter), to, amount));
    }

    function proveFail_transferFrom_falseReturner(address from, address to, uint256 amount) public {
        require(ERC20Helper.transferFrom(address(falseReturner), from, to, amount));
    }

    function proveFail_transferFrom_reverter(address from, address to, uint256 amount) public {
        require(ERC20Helper.transferFrom(address(reverter), from, to, amount));
    }

    function proveFail_approve_falseReturner(address to, uint256 amount) public {
        require(ERC20Helper.approve(address(falseReturner), to, amount));
    }

    function proveFail_approve_reverter(address to, uint256 amount) public {
        require(ERC20Helper.approve(address(reverter), to, amount));
    }

}
