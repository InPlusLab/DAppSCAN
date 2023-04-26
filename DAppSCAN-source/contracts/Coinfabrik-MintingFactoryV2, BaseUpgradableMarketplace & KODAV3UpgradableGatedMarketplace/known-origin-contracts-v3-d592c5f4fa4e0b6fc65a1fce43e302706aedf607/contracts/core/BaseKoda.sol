// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IKOAccessControlsLookup} from "../access/IKOAccessControlsLookup.sol";
import {IKODAV3} from "./IKODAV3.sol";
import {Konstants} from "./Konstants.sol";

abstract contract BaseKoda is Konstants, Context, IKODAV3 {

    bytes4 constant internal ERC721_RECEIVED = bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"));

    event AdminUpdateSecondaryRoyalty(uint256 _secondarySaleRoyalty);
    event AdminUpdateBasisPointsModulo(uint256 _basisPointsModulo);
    event AdminUpdateModulo(uint256 _modulo);
    event AdminEditionReported(uint256 indexed _editionId, bool indexed _reported);
    event AdminArtistAccountReported(address indexed _account, bool indexed _reported);
    event AdminUpdateAccessControls(IKOAccessControlsLookup indexed _oldAddress, IKOAccessControlsLookup indexed _newAddress);

    modifier onlyContract(){
        _onlyContract();
        _;
    }

    function _onlyContract() private view {
        require(accessControls.hasContractRole(_msgSender()), "Must be contract");
    }

    modifier onlyAdmin(){
        _onlyAdmin();
        _;
    }

    function _onlyAdmin() private view {
        require(accessControls.hasAdminRole(_msgSender()), "Must be admin");
    }

    IKOAccessControlsLookup public accessControls;

    // A onchain reference to editions which have been reported for some infringement purposes to KO
    mapping(uint256 => bool) public reportedEditionIds;

    // A onchain reference to accounts which have been lost/hacked etc
    mapping(address => bool) public reportedArtistAccounts;

    // Secondary sale commission
    uint256 public secondarySaleRoyalty = 12_50000; // 12.5% by default

    /// @notice precision 100.00000%
    uint256 public modulo = 100_00000;

    /// @notice Basis points conversion modulo
    /// @notice This is used by the IHasSecondarySaleFees implementation which is different than EIP-2981 specs
    uint256 public basisPointsModulo = 1000;

    constructor(IKOAccessControlsLookup _accessControls) {
        accessControls = _accessControls;
    }

    function reportEditionId(uint256 _editionId, bool _reported) onlyAdmin public {
        reportedEditionIds[_editionId] = _reported;
        emit AdminEditionReported(_editionId, _reported);
    }

    function reportArtistAccount(address _account, bool _reported) onlyAdmin public {
        reportedArtistAccounts[_account] = _reported;
        emit AdminArtistAccountReported(_account, _reported);
    }

    function updateBasisPointsModulo(uint256 _basisPointsModulo) onlyAdmin public {
        require(_basisPointsModulo > 0, "Is zero");
        basisPointsModulo = _basisPointsModulo;
        emit AdminUpdateBasisPointsModulo(_basisPointsModulo);
    }

    function updateModulo(uint256 _modulo) onlyAdmin public {
        require(_modulo > 0, "Is zero");
        modulo = _modulo;
        emit AdminUpdateModulo(_modulo);
    }

    function updateSecondaryRoyalty(uint256 _secondarySaleRoyalty) onlyAdmin public {
        secondarySaleRoyalty = _secondarySaleRoyalty;
        emit AdminUpdateSecondaryRoyalty(_secondarySaleRoyalty);
    }

    function updateAccessControls(IKOAccessControlsLookup _accessControls) public onlyAdmin {
        require(_accessControls.hasAdminRole(_msgSender()), "Must be admin");
        emit AdminUpdateAccessControls(accessControls, _accessControls);
        accessControls = _accessControls;
    }

    /// @dev Allows for the ability to extract stuck ERC20 tokens
    /// @dev Only callable from admin
    function withdrawStuckTokens(address _tokenAddress, uint256 _amount, address _withdrawalAccount) onlyAdmin public {
        IERC20(_tokenAddress).transfer(_withdrawalAccount, _amount);
    }
}
