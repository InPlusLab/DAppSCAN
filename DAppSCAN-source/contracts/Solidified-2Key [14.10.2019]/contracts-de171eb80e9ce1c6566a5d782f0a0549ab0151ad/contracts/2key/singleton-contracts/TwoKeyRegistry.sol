pragma solidity ^0.4.24;

import "../libraries/Call.sol";
import "../interfaces/ITwoKeyMaintainersRegistry.sol";
import "../libraries/Utils.sol";
import "../upgradability/Upgradeable.sol";
import "./ITwoKeySingletonUtils.sol";
import "../interfaces/storage-contracts/ITwoKeyRegistryStorage.sol";


contract TwoKeyRegistry is Upgradeable, Utils, ITwoKeySingletonUtils {

    using Call for *;

    bool initialized;

    ITwoKeyRegistryStorage public PROXY_STORAGE_CONTRACT;

    /// @notice Event is emitted when a user's name is changed
    event UserNameChanged(address owner, string name);


    function isMaintainer(address x) internal view returns (bool) {
        address twoKeyMaintainersRegistry = getAddressFromTwoKeySingletonRegistry("TwoKeyMaintainersRegistry");
        return ITwoKeyMaintainersRegistry(twoKeyMaintainersRegistry).onlyMaintainer(x);
    }


    /**
     * @notice Function which can be called only once
     */
    function setInitialParams(
        address _twoKeySingletonesRegistry,
        address _proxyStorage
    )
    external
    {
        require(initialized == false);

        TWO_KEY_SINGLETON_REGISTRY = _twoKeySingletonesRegistry;
        PROXY_STORAGE_CONTRACT = ITwoKeyRegistryStorage(_proxyStorage);

        initialized = true;
    }



    /// @notice Function where new name/address pair is added or an old address is updated with new name
    /// @dev private function
    /// @param _name is name of user
    /// @param _sender is address of user
    function addNameInternal(
        string _name,
        address _sender
    )
    internal
    {
        bytes32 name = stringToBytes32(_name);

        bytes32 keyHashUserNameToAddress = keccak256("username2currentAddress", name);
        bytes32 keyHashAddressToUserName = keccak256("address2username", _sender);

        // check if name is taken
        if (PROXY_STORAGE_CONTRACT.getAddress(keyHashUserNameToAddress) != address(0)) {
            revert();
        }

        PROXY_STORAGE_CONTRACT.setString(keyHashAddressToUserName, _name);
        PROXY_STORAGE_CONTRACT.setAddress(keyHashUserNameToAddress, _sender);

        emit UserNameChanged(_sender, _name);
    }

    /**
     * @notice Function to concat this 2 functions at once
     */
    function addNameAndSetWalletName(
        string _name,
        address _sender,
        string _fullName,
        string _email,
        string _username_walletName,
        bytes _signatureName,
        bytes _signatureWalletName
    )
    public
    {
        require(isMaintainer(msg.sender));
        addName(_name, _sender, _fullName, _email, _signatureName);
        setWalletName(_name, _sender, _username_walletName, _signatureWalletName);
    }

    /// @notice Function where only admin can add a name - address pair
    /// @param _name is name of user
    /// @param _sender is address of user
    function addName(
        string _name,
        address _sender,
        string _fullName,
        string _email,
        bytes signature
    )
    public
    {
        require(isMaintainer(msg.sender)== true || msg.sender == address(this));

        string memory concatenatedValues = strConcat(_name,_fullName,_email);
        bytes32 hash = keccak256(abi.encodePacked(keccak256(abi.encodePacked("bytes binding to name")),
            keccak256(abi.encodePacked(concatenatedValues))));
        address message_signer = Call.recoverHash(hash, signature, 0);
        require(message_signer == _sender);
        bytes32 keyHashUsername = keccak256("addressToUserData", "username", _sender);
        bytes32 keyHashFullName = keccak256("addressToUserData", "fullName", _sender);
        bytes32 keyHashEmail = keccak256("addressToUserData", "email", _sender);

        PROXY_STORAGE_CONTRACT.setString(keyHashUsername, _name);
        PROXY_STORAGE_CONTRACT.setString(keyHashFullName, _fullName);
        PROXY_STORAGE_CONTRACT.setString(keyHashEmail, _email);

        addNameInternal(_name, _sender);
    }

    /// @notice Add signed name
    /// @param _name is the name
    /// @param external_sig is the external signature
    function addNameSigned(
        string _name,
        bytes external_sig
    )
    public
    {
        bytes32 hash = keccak256(abi.encodePacked(keccak256(abi.encodePacked("bytes binding to name")),
            keccak256(abi.encodePacked(_name))));
        address eth_address = Call.recoverHash(hash,external_sig,0);
        require (msg.sender == eth_address || isMaintainer(msg.sender) == true, "only maintainer or user can change name");
        addNameInternal(_name, eth_address);
    }

    function setNoteInternal(
        bytes note,
        address me
    )
    private
    {
        bytes32 keyHashNotes = keccak256("notes", me);
        PROXY_STORAGE_CONTRACT.setBytes(keyHashNotes, note);
    }

    function setNoteByUser(
        bytes note
    )
    public
    {
        // note is a message you can store with sig. For example it could be the secret you used encrypted by you
        setNoteInternal(note, msg.sender);
    }


    /// @notice Function where TwoKeyMaintainer can add walletname to address
    /// @param username is the username of the user we want to update map for
    /// @param _address is the address of the user we want to update map for
    /// @param _username_walletName is the concatenated username + '_' + walletName, since sending from trusted provider no need to validate
    function setWalletName(
        string memory username,
        address _address,
        string memory _username_walletName,
        bytes signature
    )
    public
    {
        require(isMaintainer(msg.sender) == true || msg.sender == address(this));
        require(_address != address(0));
        bytes32 usernameHex = stringToBytes32(username);
        address usersAddress = PROXY_STORAGE_CONTRACT.getAddress(keccak256("username2currentAddress", usernameHex));
        require(usersAddress == _address); // validating that username exists

        string memory concatenatedValues = strConcat(username,_username_walletName,"");

        bytes32 hash = keccak256(abi.encodePacked(keccak256(abi.encodePacked("bytes binding to name")),
            keccak256(abi.encodePacked(concatenatedValues))));
        address message_signer = Call.recoverHash(hash, signature, 0);
        require(message_signer == _address);

        bytes32 walletTag = stringToBytes32(_username_walletName);
        bytes32 keyHashAddress2WalletTag = keccak256("address2walletTag", _address);
        PROXY_STORAGE_CONTRACT.setBytes32(keyHashAddress2WalletTag, walletTag);

        bytes32 keyHashWalletTag2Address = keccak256("walletTag2address", walletTag);
        PROXY_STORAGE_CONTRACT.setAddress(keyHashWalletTag2Address, _address);
    }

    function addPlasma2EthereumInternal(
        bytes sig,
        address eth_address
    )
    private
    {
        // add an entry connecting msg.sender to the ethereum address that was used to sign sig.
        // see setup_demo.js on how to generate sig
        bytes32 hash = keccak256(abi.encodePacked(keccak256(abi.encodePacked("bytes binding to ethereum address")),keccak256(abi.encodePacked(eth_address))));
        address plasma_address = Call.recoverHash(hash,sig,0);
        bytes32 keyHashPlasmaToEthereum = keccak256("plasma2ethereum", plasma_address);
        bytes32 keyHashEthereumToPlasma = keccak256("ethereum2plasma", eth_address);

        require(PROXY_STORAGE_CONTRACT.getAddress(keyHashPlasmaToEthereum) == address(0) || PROXY_STORAGE_CONTRACT.getAddress(keyHashPlasmaToEthereum) == eth_address, "cant change eth=>plasma");

        PROXY_STORAGE_CONTRACT.setAddress(keyHashPlasmaToEthereum, eth_address);
        PROXY_STORAGE_CONTRACT.setAddress(keyHashEthereumToPlasma, plasma_address);
    }

    function addPlasma2EthereumByUser(
        bytes sig
    )
    public
    {
        addPlasma2EthereumInternal(sig, msg.sender);
    }

    function setPlasma2EthereumAndNoteSigned(
        bytes sig,
        bytes note,
        bytes external_sig
    )
    public
    {
        bytes32 hash = keccak256(abi.encodePacked(keccak256(abi.encodePacked("bytes binding to ethereum-plasma")),
            keccak256(abi.encodePacked(sig,note))));
        address eth_address = Call.recoverHash(hash,external_sig,0);
        require (msg.sender == eth_address || isMaintainer(msg.sender), "only maintainer or user can change ethereum-plasma");
        addPlasma2EthereumInternal(sig, eth_address);
        setNoteInternal(note, eth_address);
    }

    /// View function - doesn't cost any gas to be executed
    /// @notice Function to fetch address of the user that corresponds to given name
    /// @param _name is name of user
    /// @return address of the user as type address
    function getUserName2UserAddress(
        string _name
    )
    external
    view
    returns (address)
    {
        bytes32 name = stringToBytes32(_name);
        return PROXY_STORAGE_CONTRACT.getAddress(keccak256("username2currentAddress", _name));
    }

    /// View function - doesn't cost any gas to be executed
    /// @notice Function to fetch name that corresponds to the address
    /// @param _sender is address of user
    /// @return name of the user as type string
    function getUserAddress2UserName(
        address _sender
    )
    external
    view
    returns (string)
    {
        return PROXY_STORAGE_CONTRACT.getString(keccak256("address2username", _sender));
    }

//    /**
//     */
//    function deleteUser(
//        string userName
//    )
//    public
//    {
//        require(isMaintainer(msg.sender));
//        bytes32 userNameHex = stringToBytes32(userName);
//        address _ethereumAddress = username2currentAddress[userNameHex];
//        username2currentAddress[userNameHex] = address(0);
//
//        address2username[_ethereumAddress] = "";
//
//        bytes32 walletTag = address2walletTag[_ethereumAddress];
//        address2walletTag[_ethereumAddress] = bytes32(0);
//        walletTag2address[walletTag] = address(0);
//
//        address plasma = ethereum2plasma[_ethereumAddress];
//        ethereum2plasma[_ethereumAddress] = address(0);
//        PROXY_STORAGE_CONTRACT.deleteAddress()
//        plasma2ethereum[plasma] = address(0);
//
//        UserData memory userdata = addressToUserData[_ethereumAddress];
//        userdata.username = "";
//        userdata.fullName = "";
//        userdata.email = "";
//        addressToUserData[_ethereumAddress] = userdata;
//
//        notes[_ethereumAddress] = "";
//    }


    /**
     * @notice Reading from mapping ethereum 2 plasma
     * @param plasma is the plasma address we're searching eth address for
     * @return ethereum address if exist otherwise 0x0 (address(0))
     */
    function getPlasmaToEthereum(
        address plasma
    )
    public
    view
    returns (address)
    {
        bytes32 keyHashPlasmaToEthereum = keccak256("plasma2ethereum", plasma);
        address ethereum = PROXY_STORAGE_CONTRACT.getAddress(keyHashPlasmaToEthereum);
        if(ethereum!= address(0)) {
            return ethereum;
        }
        return plasma;
    }

    /**
     * @notice Reading from mapping plasma 2 ethereum
     * @param ethereum is the ethereum address we're searching plasma address for
     * @return plasma address if exist otherwise 0x0 (address(0))
     */
    function getEthereumToPlasma(
        address ethereum
    )
    public
    view
    returns (address)
    {
        bytes32 keyHashEthereumToPlasma = keccak256("ethereum2plasma", ethereum);
        address plasma = PROXY_STORAGE_CONTRACT.getAddress(keyHashEthereumToPlasma);
        if(plasma != address(0)) {
            return plasma;
        }
        return ethereum;
    }


    /**
     * @notice Function to check if the user exists
     * @param _userAddress is the address of the user
     * @return true if exists otherwise false
     */
    function checkIfUserExists(
        address _userAddress
    )
    external
    view
    returns (bool)
    {
        string memory username = PROXY_STORAGE_CONTRACT.getString(keccak256("address2username", _userAddress));
        bytes memory tempEmptyStringTest = bytes(username);
        bytes32 keyHashEthereumToPlasma = keccak256("ethereum2plasma", _userAddress);
        address plasma = PROXY_STORAGE_CONTRACT.getAddress(keyHashEthereumToPlasma);
        //notes[_userAddress].length == 0
        bytes memory savedNotes = PROXY_STORAGE_CONTRACT.getBytes(keccak256("notes", _userAddress));
        bytes32 walletTag = PROXY_STORAGE_CONTRACT.getBytes32(keccak256("address2walletTag", _userAddress));
        if(tempEmptyStringTest.length == 0 || walletTag == 0 || plasma == address(0) || savedNotes.length == 0) {
            return false;
        }
        return true;
    }


    function getUserData(
        address _user
    )
    external
    view
    returns (bytes)
    {
        bytes32 keyHashUsername = keccak256("addressToUserData", "username", _user);
        bytes32 keyHashFullName = keccak256("addressToUserData", "fullName", _user);
        bytes32 keyHashEmail = keccak256("addressToUserData", "email", _user);


        bytes32 username = stringToBytes32(PROXY_STORAGE_CONTRACT.getString(keyHashUsername));
        bytes32 fullName = stringToBytes32(PROXY_STORAGE_CONTRACT.getString(keyHashFullName));
        bytes32 email = stringToBytes32(PROXY_STORAGE_CONTRACT.getString(keyHashEmail));

        return (abi.encodePacked(username, fullName, email));
    }

    function notes(
        address keyAddress
    )
    public
    view
    returns (bytes)
    {
        return PROXY_STORAGE_CONTRACT.getBytes(keccak256("notes", keyAddress));
    }

    function address2walletTag(
        address keyAddress
    )
    public
    view
    returns (bytes32)
    {
        return PROXY_STORAGE_CONTRACT.getBytes32(keccak256("address2walletTag", keyAddress));
    }

    function walletTag2address(
        bytes32 walletTag
    )
    public
    view
    returns (address)
    {
        return PROXY_STORAGE_CONTRACT.getAddress(keccak256("walletTag2address", walletTag));
    }

    function address2username(
        address keyAddress
    )
    public
    view
    returns (string)
    {
        return PROXY_STORAGE_CONTRACT.getString(keccak256("address2username", keyAddress));
    }

    function username2currentAddress(
        bytes32 _username
    )
    public
    view
    returns (address)
    {
        return PROXY_STORAGE_CONTRACT.getAddress(keccak256("username2currentAddress", _username));
    }



}
