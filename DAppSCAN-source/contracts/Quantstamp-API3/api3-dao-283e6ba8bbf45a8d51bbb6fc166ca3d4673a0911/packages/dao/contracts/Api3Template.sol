//SPDX-License-Identifier: MIT
pragma solidity 0.4.24;

import "@aragon/templates-shared/contracts/BaseTemplate.sol";
import "@api3-dao/api3-voting/contracts/Api3Voting.sol";

contract Api3Template is BaseTemplate {
//    Comment below is ID for Rinkeby/Mainnet
//    bytes32 constant internal API3_VOTING_APP_ID = 0x323c4eb511f386e7972d45b948cc546db35e9ccc7161c056fb07e09abd87e554;
    bytes32 constant internal API3_VOTING_APP_ID = 0x727a0cf100ef0e645bad5a5b920d7fb71f8fd0eaf0fa579c341a045f597526f5;
    string constant private ERROR_BAD_VOTE_SETTINGS = "API3_DAO_BAD_VOTE_SETTINGS";

    address private constant ANY_ENTITY = address(-1);

    event Api3DaoDeployed(
      address dao,
      address acl,
      address api3Pool,
      address mainVoting,
      address secondaryVoting,
      address mainAgent,
      address secondaryAgent
    );

    constructor(
      DAOFactory _daoFactory,
      ENS _ens,
      MiniMeTokenFactory _minimeTokenFactory,
      IFIFSResolvingRegistrar _aragonID
    )
    public
    BaseTemplate(_daoFactory, _ens, _minimeTokenFactory, _aragonID)
    {
        _ensureAragonIdIsValid(_aragonID);
    }

    /**
    * @dev Deploy an authoritative DAO using the API3 Staking Pool
    * @param _id String with the name for org, will assign `[id].aragonid.eth`
    * @param _api3Pool Address of the API3 staking pool, supplies voting power
    * @param _mainVotingSettings Array of [supportRequired, minAcceptanceQuorum, voteDuration] to set up the voting app of the organization
    * @param _secondaryVotingSettings Array of [supportRequired, minAcceptanceQuorum, voteDuration] to set up the voting app of the organization
    */
    function newInstance(
        string memory _id,
        MiniMeToken _api3Pool,
        uint64[3] memory _mainVotingSettings,
        uint64[3] memory _secondaryVotingSettings
    )
    public
    {
        require(_api3Pool != address(0), "Invalid API3 Api3Voting Rights");

        _validateId(_id);
        _validateVotingSettings(_mainVotingSettings);
        _validateVotingSettings(_secondaryVotingSettings);

        (Kernel dao, ACL acl) = _createDAO();
        (Api3Voting mainVoting, Api3Voting secondaryVoting, Agent mainAgent, Agent secondaryAgent) = _setupApps(
            dao, acl, _api3Pool, _mainVotingSettings,_secondaryVotingSettings
        );
        _transferRootPermissionsFromTemplateAndFinalizeDAO(dao, mainVoting);
        _registerID(_id, dao);

        emit Api3DaoDeployed(
            address(dao),
            address(acl),
            address(_api3Pool),
            address(mainVoting),
            address(secondaryVoting),
            address(mainAgent),
            address(secondaryAgent)
        );
    }

    function _setupApps(
        Kernel _dao,
        ACL _acl,
        MiniMeToken _api3Pool,
        uint64[3] memory _mainVotingSettings,
        uint64[3] memory _secondaryVotingSettings
    )
    internal
    returns (Api3Voting, Api3Voting, Agent, Agent)
    {
        Agent mainAgent = _installDefaultAgentApp(_dao);
        Agent secondaryAgent = _installNonDefaultAgentApp(_dao);
        Api3Voting mainVoting = _installApi3VotingApp(_dao, _api3Pool, _mainVotingSettings);
        Api3Voting secondaryVoting = _installApi3VotingApp(_dao, _api3Pool, _secondaryVotingSettings);

        _setupPermissions(
            _acl,
            mainAgent,
            mainVoting,
            secondaryAgent,
            secondaryVoting,
            mainVoting
        );

        return (mainVoting, secondaryVoting, mainAgent, secondaryAgent);
    }

    function _setupPermissions(
        ACL _acl,
        Agent _mainAgent,
        Api3Voting _mainVoting,
        Agent _secondaryAgent,
        Api3Voting _secondaryVoting,
        address _permissionManager
    )
    internal
    {
        _createAgentPermissions(_acl, _mainAgent, _mainVoting, _permissionManager);
        _createAgentPermissions(_acl, _secondaryAgent, _secondaryVoting, _permissionManager);
        _createVaultPermissions(_acl, Vault(_mainAgent), _mainVoting, _permissionManager);
        _createVaultPermissions(_acl, Vault(_secondaryAgent), _secondaryVoting, _permissionManager);
        _createEvmScriptsRegistryPermissions(_acl, _permissionManager, _permissionManager);
        _createApi3VotingPermissions(_acl, _mainVoting, _mainAgent, ANY_ENTITY, _permissionManager);
        _createApi3VotingPermissions(_acl, _secondaryVoting, _mainAgent, ANY_ENTITY, _permissionManager);
    }

    function _validateVotingSettings(uint64[3] memory _votingSettings) private pure {
        require(_votingSettings.length == 3, ERROR_BAD_VOTE_SETTINGS);
    }

    /*API3 VOTING*/

    function _installApi3VotingApp(Kernel _dao, MiniMeToken _token, uint64[3] memory _votingSettings) internal returns (Api3Voting) {
        return _installApi3VotingApp(_dao, _token, _votingSettings[0], _votingSettings[1], _votingSettings[2]);
    }

    function _installApi3VotingApp(
        Kernel _dao,
        MiniMeToken _token,
        uint64 _support,
        uint64 _acceptance,
        uint64 _duration
    )
    internal returns (Api3Voting)
    {
        bytes memory initializeData = abi.encodeWithSelector(Api3Voting(0).initialize.selector, _token, _support, _acceptance, _duration);
        return Api3Voting(_installNonDefaultApp(_dao, API3_VOTING_APP_ID, initializeData));
    }

    function _createApi3VotingPermissions(
        ACL _acl,
        Api3Voting _voting,
        address _settingsGrantee,
        address _createVotesGrantee,
        address _manager
    )
    internal
    {
        _acl.createPermission(_settingsGrantee, _voting, _voting.MODIFY_QUORUM_ROLE(), _manager);
        _acl.createPermission(_settingsGrantee, _voting, _voting.MODIFY_SUPPORT_ROLE(), _manager);
        _acl.createPermission(_createVotesGrantee, _voting, _voting.CREATE_VOTES_ROLE(), _manager);
    }
}
