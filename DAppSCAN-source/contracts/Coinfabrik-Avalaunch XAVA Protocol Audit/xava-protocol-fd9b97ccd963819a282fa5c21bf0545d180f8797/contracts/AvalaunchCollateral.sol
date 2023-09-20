// SPDX-License-Identifier: UNLICENSED
// SWC-102-Outdated Compiler Version: L4
// SWC-103-Floating Pragma: L4
pragma solidity ^0.6.12;

import "@openzeppelin/contracts/proxy/Initializable.sol";
import "@openzeppelin/contracts/cryptography/ECDSA.sol";
import "./math/SafeMath.sol";
import "./interfaces/IAvalaunchSale.sol";
import "./Admin.sol";

contract AvalaunchCollateral is Initializable {

    using SafeMath for uint256;

    Admin public admin;
    // Accounting total fees collected by the contract
    uint256 public totalFeesCollected;
    // Moderator of the contract.
    address public moderator;
    // Mapping if sale is approved by moderator for the autobuys
    mapping (address => bool) public isSaleApprovedByModerator;
    // Mapping if signature is used
    mapping (bytes => bool) public isSignatureUsed;
    // Mapping for autoBuy users per sale
    mapping (address => mapping (address => bool)) public saleAutoBuyers;
    // User to his collateral balance
    mapping (address => uint256) public userBalance;

    // AUTOBUY - TYPE / TYPEHASH / MESSAGEHASH
    string public constant AUTOBUY_TYPE = "AutoBuy(string confirmationMessage,address saleAddress)";
    bytes32 public constant AUTOBUY_TYPEHASH = keccak256(abi.encodePacked(AUTOBUY_TYPE));
    bytes32 public constant AUTOBUY_MESSAGEHASH = keccak256("Turn AutoBUY ON.");

    // BOOST - TYPE / TYPEHASH / MESSAGEHASH
    string public constant BOOST_TYPE = "Boost(string confirmationMessage,address saleAddress)";
    bytes32 public constant BOOST_TYPEHASH = keccak256(abi.encodePacked(BOOST_TYPE));
    bytes32 public constant BOOST_MESSAGEHASH = keccak256("Boost participation.");

    // DOMAIN - TYPE / TYPEHASH / SEPARATOR
    string public constant EIP712_DOMAIN = "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)";
    bytes32 public constant EIP712_DOMAIN_TYPEHASH = keccak256(abi.encodePacked(EIP712_DOMAIN));
    bytes32 public DOMAIN_SEPARATOR;

    event DepositedCollateral(address indexed wallet, uint256 amountDeposited, uint256 timestamp);
    event WithdrawnCollateral(address indexed wallet, uint256 amountWithdrawn, uint256 timestamp);
    event FeeTaken(address indexed sale, uint256 participationAmount, uint256 feeAmount, string action);
    event ApprovedSale(address indexed sale);

    modifier onlyAdmin {
        require(admin.isAdmin(msg.sender), "Only admin.");
        _;
    }

    modifier onlyModerator {
        require(msg.sender == moderator, "Only moderator.");
        _;
    }

    /**
     * @notice  Initializer - setting initial parameters on the contract
     * @param   _moderator is the address of moderator, which will be used to receive
     *          proceeds from the fees, and has permissions to approve sales for autobuy
     * @param   _admin is the address of Admin contract
     */
    function initialize(address _moderator, address _admin, uint256 chainId) external initializer {
        // Perform zero address checks
        require(_moderator != address(0x0), "Moderator can not be 0x0.");
        require(_admin != address(0x0), "Admin can not be 0x0.");

        // Assign globals
        moderator = _moderator;
        admin = Admin(_admin);

        // Compute domain separator
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                EIP712_DOMAIN_TYPEHASH,
                keccak256("AvalaunchApp"),
                keccak256("1"),
                chainId,
                address(this)
            )
        );
    }

    // Internal function to handle safe transfer
    function safeTransferAVAX(address to, uint256 value) internal {
        (bool success, ) = to.call{value: value}(new bytes(0));
        require(success);
    }

    /**
     * @notice  Function to collateralize AVAX by user.
     */
    function depositCollateral() external payable {
        userBalance[msg.sender] = userBalance[msg.sender].add(msg.value);
        emit DepositedCollateral(
            msg.sender,
            msg.value,
            block.timestamp
        );
    }

    /**
     * @notice  Function where user can withdraw his collateralized funds from the contract
     * @param   _amount is the amount of AVAX user is willing to withdraw.
     *          It can't exceed his collateralized amount.
     */
    function withdrawCollateral(uint256 _amount) external {
        require(userBalance[msg.sender] >= _amount, "Not enough funds.");

        userBalance[msg.sender] = userBalance[msg.sender].sub(_amount);
        safeTransferAVAX(msg.sender, _amount);

        emit WithdrawnCollateral(
            msg.sender,
            _amount,
            block.timestamp
        );
    }

    /**
     * @notice  Function for auto participation, where admin can participate on user behalf and buy him allocation
     *          by taking funds from his collateral.
     * @dev     Function is restricted only to admins.
     * @param   saleAddress is the address of the sale contract in which admin participates
     * @param   amountAVAX is the amount of AVAX which will be taken from user to get him an allocation.
     * @param   amount is the amount of tokens user is allowed to buy (maximal)
     * @param   amountXavaToBurn is the amount of XAVA which will be taken from user and redistributed across
     *          other Avalaunch stakers
     * @param   roundId is the ID of the round for which participation is being taken.
     * @param   user is the address of user on whose behalf this action is being done.
     * @param   participationFeeAVAX is the FEE amount which is taken by Avalaunch for this service.
     * @param   permitSignature is the approval from user side to take his funds for specific sale address
     */
    function autoParticipate(
        address saleAddress,
        uint256 amountAVAX,
        uint256 amount,
        uint256 amountXavaToBurn,
        uint256 roundId,
        address user,
        uint256 participationFeeAVAX,
        bytes calldata permitSignature
    )
    external
    onlyAdmin
    {
        // Require that sale contract is approved by moderator
        require(isSaleApprovedByModerator[saleAddress], "Sale contract not approved by moderator.");
        // Require that signature is not used
        require(!isSignatureUsed[permitSignature], "Signature already used.");
        // Mark signature as used
        isSignatureUsed[permitSignature] = true;
        // Require that user does not have autoBuy activated
        require(!saleAutoBuyers[saleAddress][user], "User autoBuy already active.");
        // Mark autoBuy as active for user
        saleAutoBuyers[saleAddress][user] = true;
        // Verify that user approved with his signature this feature
        require(verifyAutoBuySignature(user, saleAddress, permitSignature), "AutoBuy signature invalid.");
        // Require that user deposited enough collateral
        require(amountAVAX.add(participationFeeAVAX) <= userBalance[user], "Not enough collateral.");
        // Reduce user balance
        userBalance[user] = userBalance[user].sub(amountAVAX.add(participationFeeAVAX));
        // Increase total fees collected
        totalFeesCollected = totalFeesCollected.add(participationFeeAVAX);

        // Transfer AVAX fee immediately to beneficiary
        safeTransferAVAX(moderator, participationFeeAVAX);
        // Trigger event
        emit FeeTaken(saleAddress, amountAVAX, participationFeeAVAX, "autoParticipate");

        // Participate
        IAvalaunchSale(saleAddress).autoParticipate{
            value: amountAVAX
        }(user, amount, amountXavaToBurn, roundId);
    }

    /**
     * @notice  Function for participation boosting, where admin can boost participation on user behalf and
     *          buy him allocation by taking funds from his collateral.
     * @dev     Function is restricted only to admins.
     * @param   saleAddress is the address of the sale contract in which admin boosts allocation for
     * @param   amountAVAX is the amount of AVAX which will be taken from user to get him an allocation.
     * @param   amount is the amount of tokens user is allowed to buy (maximal)
     * @param   amountXavaToBurn is the amount of XAVA which will be taken from user and redistributed across
     *          other Avalaunch stakers
     * @param   roundId is the ID of the round for which participation is being taken.
     * @param   user is the address of user on whose behalf this action is being done.
     * @param   boostFeeAVAX is the FEE amount which is taken by Avalaunch for this service.
     * @param   permitSignature is the approval from user side to take his funds for specific sale address
     */
    function boostParticipation(
        address saleAddress,
        uint256 amountAVAX,
        uint256 amount,
        uint256 amountXavaToBurn,
        uint256 roundId,
        address user,
        uint256 boostFeeAVAX,
        bytes calldata permitSignature
    )
    external
    onlyAdmin
    {
        // Require that sale contract is approved by moderator
        require(isSaleApprovedByModerator[saleAddress], "Sale contract not approved by moderator.");
        // Require that user deposited enough collateral
        require(amountAVAX.add(boostFeeAVAX) <= userBalance[user], "Not enough collateral.");
        // Reduce user's balance
        userBalance[user] = userBalance[user].sub(amountAVAX.add(boostFeeAVAX));
        // Require that signature is not used already
        require(!isSignatureUsed[permitSignature], "Signature already used.");
        // Mark signature as used
        isSignatureUsed[permitSignature] = true;
        // Require that boost signature is valid
        require(verifyBoostSignature(user, saleAddress, permitSignature), "Boost signature invalid.");
        // Transfer AVAX fee immediately to beneficiary
        safeTransferAVAX(moderator, boostFeeAVAX);
        // Trigger event
        emit FeeTaken(saleAddress, amountAVAX, boostFeeAVAX, "boostParticipation");

        // Participate
        IAvalaunchSale(saleAddress).boostParticipation{
            value: amountAVAX
        }(user, amount, amountXavaToBurn, roundId);
    }

    /**
     * @notice  Function to set new moderator. Can be only called by current moderator
     * @param   _moderator is the address of new moderator to be set.
     */
    function setModerator(address _moderator) onlyModerator external {
        require(_moderator != address(0x0), "Moderator can not be 0x0");
        moderator = _moderator;
    }

    /**
     * @notice  Function to approve sale for AutoBuy feature.
     * @param   saleAddress is the address of the sale contract
     */
    function approveSale(address saleAddress) onlyModerator external {
        // Set that sale is approved by moderator
        isSaleApprovedByModerator[saleAddress] = true;
        // Trigger event
        emit ApprovedSale(saleAddress);
    }

    /**
     * @notice  Function to verify that user gave permission that his collateral can be
     *          and used to participate in the specific sale
     * @param   user is the address of user
     * @param   saleContract is the address of sale contract which user allowed admin to participate
     *          on his behalf
     * @param   permitSignature is the message signed by user, allowing admin to send transaction on his behalf
     */
    function verifyAutoBuySignature(
        address user,
        address saleContract,
        bytes memory permitSignature
    )
    public
    view
    returns (bool)
    {
        // Generate v4 signature hash
        bytes32 hash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR,
                keccak256(
                    abi.encode(
                        AUTOBUY_TYPEHASH,
                        AUTOBUY_MESSAGEHASH,
                        saleContract
                    )
                )
            )
        );

        return user == ECDSA.recover(hash, permitSignature);
    }

    /**
     * @notice  Function to verify that user gave permission that his collateral can be
     *          and used to boost his sale participation
     * @param   user is the address of user
     * @param   saleContract is the address of sale contract which user allowed admin to participate
     *          on his behalf
     * @param   permitSignature is the message signed by user, allowing admin to send transaction on his behalf
     */
    function verifyBoostSignature(
        address user,
        address saleContract,
        bytes memory permitSignature
    )
    public
    view
    returns (bool)
    {
        // Generate v4 signature hash
        bytes32 hash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR,
                keccak256(
                    abi.encode(
                        BOOST_TYPEHASH,
                        BOOST_MESSAGEHASH,
                        saleContract
                    )
                )
            )
        );

        return user == ECDSA.recover(hash, permitSignature);
    }

    /**
     * @notice  Function to get total collateralized amount of AVAX by users.
     */
    function getTVL() external view returns (uint256) {
        return address(this).balance;
    }
}
