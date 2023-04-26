// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;
import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import "./interfaces/IMetaERC20.sol";


contract MetaERC20 is ERC20PresetMinterPauser, IMetaERC20 {
    address public override meta;
    uint256 public override assetId;
    bytes public override data;
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
    constructor(string memory name, string memory symbol, address meta, uint256 assetId, bytes memory data) ERC20PresetMinterPauser(name, symbol) public {
        _setupRole(MINTER_ROLE, msg.sender);
        meta = meta;
        assetId = assetId;
        data = data;
    }
    function mint(address to, uint256 amount) public virtual override(ERC20PresetMinterPauser, IMetaERC20) {
        require(hasRole(MINTER_ROLE, _msgSender()), "ERC20PresetMinterPauser: must have minter role to mint");
        _mint(to, amount);
    }

    function burn(address to, uint256 amount) public virtual override(IMetaERC20) {
        require(hasRole(BURNER_ROLE, _msgSender()), "ERC20PresetMinterPauser: must have burner role to burn");
        _burn(to, amount);
    }
}