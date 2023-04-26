pragma solidity ^0.4.24;
import "./ITwoKeyCampaignPublicAddresses.sol";

/**
 * @author Nikola Madjarevic
 * Created at 2/4/19
 */
contract ITwoKeyAcquisitionCampaignStateVariables is ITwoKeyCampaignPublicAddresses {
    address public twoKeyAcquisitionLogicHandler;
    address public conversionHandler;

    function getInventoryBalance() public view returns (uint);
}
