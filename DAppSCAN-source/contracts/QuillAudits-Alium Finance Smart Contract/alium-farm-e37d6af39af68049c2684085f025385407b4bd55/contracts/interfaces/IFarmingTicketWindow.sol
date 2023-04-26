pragma solidity =0.6.12;

interface IFarmingTicketWindow {
    function hasTicket(address account) external view returns (bool);
}
