// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./libs/ShibaBEP20.sol";

contract NovaToken is ShibaBEP20("Shiba NOVA", "NOVA") {

    address public sNova;

    /*
     * @dev Throws if called by any account other than the owner or sNova
     */
    modifier onlyOwnerOrSNova() {
        require(isOwner() || isSNova(), "caller is not the owner or sNova");
        _;
    }

    /**
     * @dev Returns true if the caller is the current owner.
     */
    function isOwner() public view returns (bool) {
        return msg.sender == owner();
    }

    /**
     * @dev Returns true if the caller is sNova contracts.
     */
    function isSNova() internal view returns (bool) {
        return msg.sender == address(sNova);
    }

    function setupSNova(address _sNova) external onlyOwner{
        sNova = _sNova;
    }

    /// @notice Creates `_amount` token to `_to`. Must only be called by the owner (MasterShiba).
    function mint(address _to, uint256 _amount) external virtual override onlyOwnerOrSNova  {
        _mint(_to, _amount);
    }


    /// @dev overrides transfer function to meet tokenomics of Nova
    function _transfer(address sender, address recipient, uint256 amount) internal virtual override {
        require(amount > 0, "amount 0");
        if (recipient == BURN_ADDRESS) {
            super._burn(sender, amount);
        } else {
            // 2% of every transfer burnt
            uint256 burnAmount = amount.mul(2).div(100);
            // 98% of transfer sent to recipient
            uint256 sendAmount = amount.sub(burnAmount);
            require(amount == sendAmount + burnAmount, "Nova::transfer: Burn value invalid");

            super._burn(sender, burnAmount);
            super._transfer(sender, recipient, sendAmount);
            amount = sendAmount;
        }
    }

}