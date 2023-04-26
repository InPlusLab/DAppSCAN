pragma solidity ^0.4.24;


contract ITwoKeyReg {
    function addTwoKeyEventSource(address _twoKeyEventSource) public;
    function changeTwoKeyEventSource(address _twoKeyEventSource) public;
    function addWhereContractor(address _userAddress, address _contractAddress) public;
    function addWhereModerator(address _userAddress, address _contractAddress) public;
    function addWhereReferrer(address _userAddress, address _contractAddress) public;
    function addWhereConverter(address _userAddress, address _contractAddress) public;
    function getContractsWhereUserIsContractor(address _userAddress) public view returns (address[]);
    function getContractsWhereUserIsModerator(address _userAddress) public view returns (address[]);
    function getContractsWhereUserIsRefferer(address _userAddress) public view returns (address[]);
    function getContractsWhereUserIsConverter(address _userAddress) public view returns (address[]);
    function getTwoKeyEventSourceAddress() public view returns (address);
    function addName(string _name, address _sender, string _fullName, string _email, bytes signature) public;
    function addNameByUser(string _name) public;
    function getName2Owner(string _name) public view returns (address);
    function getOwner2Name(address _sender) public view returns (string);
    function getPlasmaToEthereum(address plasma) public view returns (address);
    function getEthereumToPlasma(address ethereum) public view returns (address);
    function checkIfTwoKeyMaintainerExists(address _maintainer) public view returns (bool);
    function getUserData(address _user) external view returns (bytes);
}
