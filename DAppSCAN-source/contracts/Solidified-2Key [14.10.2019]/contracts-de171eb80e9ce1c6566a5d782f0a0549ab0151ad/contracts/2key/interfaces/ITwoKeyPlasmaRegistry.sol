pragma solidity ^0.4.24;

contract ITwoKeyPlasmaRegistry {
    function plasma2ethereum(
        address _plasma
    )
    public
    view
    returns (address);


    function ethereum2plasma(
        address _ethereum
    )
    public
    view
    returns (address);
}
