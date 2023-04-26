pragma solidity ^0.4.24;

import "@aragon/os/contracts/apps/AragonApp.sol";
import "@aragon/apps-agent/contracts/Agent.sol";
import "@aragon/os/contracts/common/SafeERC20.sol";
import "@aragon/os/contracts/lib/token/ERC20.sol";
import "./CErc20Interface.sol";
import "./lib/AddressArrayUtils.sol";

contract Compound is AragonApp {

    using SafeERC20 for ERC20;
    using AddressArrayUtils for address[];

    /* Hardcoded constants to save gas
        bytes32 public constant SET_AGENT_ROLE = keccak256("SET_AGENT_ROLE");
        bytes32 public constant TRANSFER_ROLE = keccak256("TRANSFER_ROLE");
        bytes32 public constant MODIFY_CTOKENS_ROLE = keccak256("MODIFY_CTOKENS_ROLE");
        bytes32 public constant SUPPLY_ROLE = keccak256("SUPPLY_ROLE");
        bytes32 public constant REDEEM_ROLE = keccak256("REDEEM_ROLE");
    */
    bytes32 public constant SET_AGENT_ROLE = 0xf57d195c0663dd0e8a2210bb519e2b7de35301795015198efff16e9a2be238c8;
    bytes32 public constant TRANSFER_ROLE = 0x8502233096d909befbda0999bb8ea2f3a6be3c138b9fbf003752a4c8bce86f6c;
    bytes32 public constant MODIFY_CTOKENS_ROLE = 0xa69ab0a4585055dc366c83c18e3585a1df44c84e1aff2c24dbe3e54fa55427ec;
    bytes32 public constant SUPPLY_ROLE = 0xbc1f3f7c406085be62d227092f4fd5af86922a19f3a87e6199f14015341eb9d9;
    bytes32 public constant REDEEM_ROLE = 0x23ab158aaf38f3699bf4266a91ca312794fa7ad6ee01e00dd03738daa058501e;

    string private constant ERROR_TOO_MANY_CERC20S = "COMPOUND_TOO_MANY_CERC20S";
    string private constant ERROR_NOT_CONTRACT = "COMPOUND_NOT_CONTRACT";
    string private constant ERROR_TOKEN_ALREADY_ADDED = "COMPOUND_ERROR_TOKEN_ALREADY_ADDED";
    string private constant ERROR_CAN_NOT_DELETE_TOKEN = "COMPOUND_CAN_NOT_DELETE_TOKEN";
    string private constant ERROR_VALUE_MISMATCH = "COMPOUND_VALUE_MISMATCH";
    string private constant ERROR_SEND_REVERTED = "COMPOUND_SEND_REVERTED";
    string private constant ERROR_TOKEN_TRANSFER_FROM_REVERTED = "COMPOUND_TOKEN_TRANSFER_FROM_REVERTED";
    string private constant ERROR_TOKEN_APPROVE_REVERTED = "COMPOUND_TOKEN_APPROVE_REVERTED";
    string private constant ERROR_TOKEN_NOT_ENABLED = "COMPOUND_TOKEN_NOT_ENABLED";
    string private constant ERROR_MINT_FAILED = "COMPOUND_MINT_FAILED";
    string private constant ERROR_REDEEM_FAILED = "COMPOUND_REDEEM_FAILED";

    uint256 public constant MAX_ENABLED_CERC20S = 100;

    Agent public agent;
    address[] public enabledCErc20s;

    event AppInitialized();
    event NewAgentSet(address agent);
    event CErc20Enabled(address cErc20);
    event CErc20Disabled(address cErc20);
    event AgentSupply();
    event AgentRedeem();

    modifier cErc20IsEnabled(address _cErc20) {
        require(enabledCErc20s.contains(_cErc20), ERROR_TOKEN_NOT_ENABLED);
        _;
    }

    /**
    * @notice Initialize the Compound App
    * @param _agent The Agent contract address
    * @param _enabledCErc20s An array of enabled tokens, should not contain duplicates.
    */
    function initialize(Agent _agent, address[] _enabledCErc20s) external onlyInit {
        require(_enabledCErc20s.length <= MAX_ENABLED_CERC20S, ERROR_TOO_MANY_CERC20S);
        require(isContract(address(_agent)), ERROR_NOT_CONTRACT);

        for (uint256 enabledTokenIndex = 0; enabledTokenIndex < _enabledCErc20s.length; enabledTokenIndex++) {
            address enabledCErc20 = _enabledCErc20s[enabledTokenIndex];
            require(isContract(enabledCErc20), ERROR_NOT_CONTRACT);
            // Sanity check that _cErc20 includes the 'underlying()' function
            CErc20Interface(enabledCErc20).underlying();
        }

        agent = _agent;
        enabledCErc20s = _enabledCErc20s;

        initialized();
        emit AppInitialized();
    }

    /**
    * @notice Update the Agent address to `_agent`
    * @param _agent New Agent address
    */
    function setAgent(Agent _agent) external auth(SET_AGENT_ROLE) {
        require(isContract(address(_agent)), ERROR_NOT_CONTRACT);

        agent = _agent;
        emit NewAgentSet(address(_agent));
    }

    /**
    * @notice Add `_cErc20' to available Compound Tokens
    * @param _cErc20 CErc20 to add
    */
    function enableCErc20(address _cErc20) external auth(MODIFY_CTOKENS_ROLE) {
        require(enabledCErc20s.length < MAX_ENABLED_CERC20S, ERROR_TOO_MANY_CERC20S);
        require(isContract(_cErc20), ERROR_NOT_CONTRACT);
        require(!enabledCErc20s.contains(_cErc20), ERROR_TOKEN_ALREADY_ADDED);

        // Sanity check that _cErc20 includes the 'underlying()' function
        CErc20Interface(_cErc20).underlying();

        enabledCErc20s.push(_cErc20);
        emit CErc20Enabled(_cErc20);
    }

    /**
    * @notice Remove `_cErc20' from available Compound Tokens
    * @param _cErc20 CErc20 to remove
    */
    function disableCErc20(address _cErc20) external auth(MODIFY_CTOKENS_ROLE) {
        require(enabledCErc20s.deleteItem(_cErc20), ERROR_CAN_NOT_DELETE_TOKEN);
        emit CErc20Disabled(_cErc20);
    }

    /**
    * @notice Get all currently enabled CErc20s
    */
    function getEnabledCErc20s() external view returns (address[]) {
        return enabledCErc20s;
    }

    /**
    * @notice Deposit `@tokenAmount(_token, _value, true, 18)` to the Compound App's Agent
    * @param _token Address of the token being transferred
    * @param _value Amount of tokens being transferred
    */
    function deposit(address _token, uint256 _value) external payable isInitialized nonReentrant {
        if (_token == ETH) {
            // Can no longer use 'send()' due to EIP-1884 so we use 'call.value()' with a reentrancy guard instead
            (bool success, ) = address(agent).call.value(_value)();
            require(success, ERROR_SEND_REVERTED);
        } else {
            require(ERC20(_token).safeTransferFrom(msg.sender, address(this), _value), ERROR_TOKEN_TRANSFER_FROM_REVERTED);
            require(ERC20(_token).safeApprove(address(agent), _value), ERROR_TOKEN_APPROVE_REVERTED);
            agent.deposit(_token, _value);
        }
    }

    /**
    * @notice Transfer `@tokenAmount(_token, _value, true, 18)` from the Compound App's Agent to `_to`
    * @param _token Address of the token being transferred
    * @param _to Address of the recipient of tokens
    * @param _value Amount of tokens being transferred
    */
    function transfer(address _token, address _to, uint256 _value) external auth(TRANSFER_ROLE) {
        agent.transfer(_token, _to, _value);
    }

    /**
    * @notice Supply `@tokenAmount(self.getUnderlyingToken(_cErc20): address, _amount, true, 18)` to Compound
    * @param _amount Amount to supply
    * @param _cErc20 CErc20 to supply to
    */
    function supplyToken(uint256 _amount, address _cErc20) external cErc20IsEnabled(_cErc20) auth(SUPPLY_ROLE)
    {
        CErc20Interface cErc20 = CErc20Interface(_cErc20);
        address token = cErc20.underlying();

        bytes memory approveFunctionCall = abi.encodeWithSignature("approve(address,uint256)", address(cErc20), _amount);
        agent.safeExecute(token, approveFunctionCall);

        bytes memory supplyFunctionCall = abi.encodeWithSignature("mint(uint256)", _amount);
        safeExecuteNoError(_cErc20, supplyFunctionCall, ERROR_MINT_FAILED);

        emit AgentSupply();
    }

    /**
    * @notice Redeem `@tokenAmount(self.getUnderlyingToken(_cErc20): address, _amount, true, 18)` from Compound
    * @param _amount Amount to redeem
    * @param _cErc20 CErc20 to redeem from
    */
    function redeemToken(uint256 _amount, address _cErc20) external cErc20IsEnabled(_cErc20) auth(REDEEM_ROLE)
    {
        bytes memory encodedFunctionCall = abi.encodeWithSignature("redeemUnderlying(uint256)", _amount);
        safeExecuteNoError(_cErc20, encodedFunctionCall, ERROR_REDEEM_FAILED);

        emit AgentRedeem();
    }

    /**
    * @notice Ensure the returned uint256 from the _data call is 0, representing a successful call
    * @param _target Address where the action is being executed
    * @param _data Calldata for the action
    */
    function safeExecuteNoError(address _target, bytes _data, string memory _error) internal {
        agent.safeExecute(_target, _data);

        uint256 callReturnValue;

        assembly {
            switch returndatasize                 // get return data size from the previous call
            case 0x20 {                           // if the return data size is 32 bytes (1 word/uint256)
                let output := mload(0x40)         // get a free memory pointer
                mstore(0x40, add(output, 0x20))   // set the free memory pointer 32 bytes
                returndatacopy(output, 0, 0x20)   // copy the first 32 bytes of data into output
                callReturnValue := mload(output)  // read the data from output
            }
            default {
                revert(0, 0) // revert on unexpected return data size
            }
        }

        require(callReturnValue == 0, _error);
    }

    /**
    * @dev Convenience function for getting token addresses in radspec strings
    * @notice Get underlying token from CErc20.
    * @param _cErc20 cErc20 to find underlying from
    */
    function getUnderlyingToken(CErc20Interface _cErc20) public view returns (address) {
        return _cErc20.underlying();
    }
}