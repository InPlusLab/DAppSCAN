pragma solidity ^0.4.10;

import '../common/Manageable.sol';
import './BCSTgeCrowdsale.sol';
import './BCSPartnerCrowdsale.sol';
import './BCSPartnerCrowdsale.sol';
import '../token/ITokenPool.sol';
import './ParticipantInvestRestrictions.sol';

contract BCSCrowdsaleFactory {

    address public controller;

    IInvestRestrictions angelSaleRestrictions;
    IInvestRestrictions tgeSaleRestrictions;

    BCSPartnerCrowdsale[] public angelSales;
    //BCSCrowdsale public preTgeSale;
    BCSTokenCrowdsale public tgeSale;

    function BCSCrowdsaleFactory(address _controller) {
        controller = _controller;
    }

    function createAngelRestrictions(uint256 floor, uint32 maxTotalInvestors) {
        angelSaleRestrictions = new ParticipantInvestRestrictions(floor, maxTotalInvestors);
        angelSaleRestrictions.setManager(msg.sender, true);
    }

    function createTgeRestrictions(uint256 floor) {
        tgeSaleRestrictions = new FloorInvestRestrictions(floor);
        tgeSaleRestrictions.setManager(msg.sender, true);
    }

    function createAngelSale(
        ITokenPool tokenPool,        
        address beneficiary,
        address partner, 
        uint16 partnerPromille, 
        uint256 startTime, 
        uint256 durationInHours, 
        uint256 tokensForOneEther,
        uint256 bonusPct) {
        
        BCSPartnerCrowdsale angelSale = new BCSPartnerCrowdsale(
            tokenPool,
            angelSaleRestrictions,
            beneficiary, 
            startTime, 
            durationInHours, 
            0, 
            tokensForOneEther,
            bonusPct,
            partner,
            partnerPromille);

        angelSaleRestrictions.setManager(angelSale, true);
        angelSale.setManager(controller, true);
        angelSale.transferOwnership(msg.sender);

        angelSales.push(angelSale);
    }

    // function createPreTge(
    //     ITokenPool tokenPool,
    //     address beneficiary, 
    //     uint256 startTime, 
    //     uint256 durationInHours, 
    //     uint256 tokensForOneEther,
    //     uint256 bonusPct, 
    //     uint256 minInvest) {
        
    //     require(address(preTgeSale) == 0x0);

    //     preTgeSale = new BCSCrowdsale(
    //         tokenPool, 
    //         beneficiary, 
    //         startTime, 
    //         durationInHours, 
    //         0, 
    //         tokensForOneEther,
    //         bonusPct,
    //         minInvest);
            
    //     preTgeSale.setManager(controller, true);
    //     preTgeSale.transferOwnership(msg.sender);
    // }

    function createTge(
        ITokenPool tokenPool,
        address beneficiary, 
        uint256 startTime, 
        uint256 durationInHours, 
        uint256 tokensForOneEther,
        uint256 bonusPct,
        uint256 steps) {

        require(address(tgeSale) == 0x0);

        tgeSale = new BCSTgeCrowdsale(
            tokenPool, 
            tgeSaleRestrictions,
            beneficiary, 
            startTime, 
            durationInHours, 
            0, 
            tokensForOneEther,
            bonusPct,
            steps);
        
        tgeSaleRestrictions.setManager(tgeSale, true);
        tgeSale.setManager(controller, true);
        tgeSale.transferOwnership(msg.sender);
    }
}