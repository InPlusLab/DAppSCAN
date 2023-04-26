pragma solidity 0.5.16;

import "@openzeppelin/contracts/introspection/IERC1820Registry.sol";
import "@openzeppelin/contracts/token/ERC777/IERC777Recipient.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "../Permissions.sol";
import "../SkaleToken.sol";


contract ReentrancyTester is Permissions, IERC777Recipient {

    IERC1820Registry private _erc1820 = IERC1820Registry(0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24);

    constructor (address _contractManager) public {
        Permissions.initialize(_contractManager);
        _erc1820.setInterfaceImplementer(address(this), keccak256("ERC777TokensRecipient"), address(this));
    }

    function tokensReceived(
        address /* operator */,
        address /* from */,
        address /* to */,
        uint256 amount,
        bytes calldata /* userData */,
        bytes calldata /* operatorData */
    )
        external
    {
        SkaleToken skaleToken = SkaleToken(contractManager.getContract("SkaleToken"));

        require(
            skaleToken.transfer(contractManager.getContract("SkaleToken"), amount),
            "Transfer is not successful");
    }
}