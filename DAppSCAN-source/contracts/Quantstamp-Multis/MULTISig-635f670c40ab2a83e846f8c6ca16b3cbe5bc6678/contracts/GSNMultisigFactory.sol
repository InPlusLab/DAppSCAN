pragma solidity ^0.5.0;

import "@openzeppelin/contracts-ethereum-package/contracts/GSN/GSNRecipientERC20Fee.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/access/roles/MinterRole.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/ownership/Ownable.sol";

import "./GSNMultiSigWalletWithDailyLimit.sol";

contract GSNMultisigFactory is GSNRecipientERC20Fee, MinterRole, Ownable {
    address[] deployedWallets;

    event ContractInstantiation(address sender, address instantiation);

    function initialize(string memory name, string memory symbol) public initializer
    {
        GSNRecipientERC20Fee.initialize(name, symbol);
        MinterRole.initialize(_msgSender());
        Ownable.initialize(_msgSender());
    }

    function mint(address account, uint256 amount) public onlyMinter {
        _mint(account, amount);
    }

    function removeMinter(address account) public onlyOwner {
        _removeMinter(account);
    }

    function getDeployedWallets() public view returns(address[] memory) {
        return deployedWallets;
    }

    function create(address[] memory _owners, uint _required, uint _dailyLimit) public returns (address wallet)
    {
        GSNMultiSigWalletWithDailyLimit multisig = new GSNMultiSigWalletWithDailyLimit();
        multisig.initialize(_owners, _required, _dailyLimit);
        wallet = address(multisig);
        deployedWallets.push(wallet);

        emit ContractInstantiation(_msgSender(), wallet);
    }
}
