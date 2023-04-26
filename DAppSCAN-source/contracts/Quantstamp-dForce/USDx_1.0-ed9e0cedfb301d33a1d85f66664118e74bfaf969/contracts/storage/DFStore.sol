pragma solidity ^0.5.2;

import '../utility/DSAuth.sol';
import '../utility/DSMath.sol';
import '../token/interfaces/IDSWrappedToken.sol';

contract DFStore is DSMath, DSAuth {
    // MEMBERS
    /// @dev  cw - The Weight of collateral
    struct Section {
        uint        minted;
        uint        burned;
        uint        backupIdx;
        address[]   colIDs;
        uint[]      cw;
    }

    Section[] public secList;

    mapping(address => address) public wrappedTokens;

    uint backupSeed = 1;
    mapping(uint => Section) public secListBackup;

    mapping(address => bool) public mintingTokens;
    mapping(address => bool) public mintedTokens;
    mapping(address => address) public tokenBackup;

    address[] public mintedTokenList;

    /// @dev The position of current secList
    uint private mintPosition;

    /// @dev The position of old secList
    uint private burnPosition;

    /// @dev  The total amount of minted.
    uint private totalMinted;

    /// @dev  The total amount of burned.
    uint private totalBurned;

    /// @dev  The minimal amount of burned.
    uint private minimalBurnAmount = 10 ** 14;

    /// @dev The total amount of collateral.
    uint private totalCol;

    mapping(uint => uint) public FeeRate;
    mapping(uint => address) public FeeToken;
    mapping(address => address) public TokenMedian;
    mapping(address => uint) public poolBalance;
    mapping(address => uint) public resUSDXBalance;
    mapping(address => mapping (address => uint)) public depositorsBalance;

    event UpdateSection(address[] _wrappedTokens, uint[] _number);

    constructor(address[] memory _wrappedTokens, uint[] memory _weights) public {
        _setSection(_wrappedTokens, _weights);
    }

    function getSectionMinted(uint _position) public view returns (uint) {
        return secList[_position].minted;
    }

    function addSectionMinted(uint _amount) public auth {
        require(_amount > 0, "AddSectionMinted: amount not correct.");
        secList[mintPosition].minted = add(secList[mintPosition].minted, _amount);
    }

    function addSectionMinted(uint _position, uint _amount) public auth {
        require(_amount > 0, "AddSectionMinted: amount not correct.");
        secList[_position].minted = add(secList[_position].minted, _amount);
    }

    function setSectionMinted(uint _amount) public auth {
        secList[mintPosition].minted = _amount;
    }

    function setSectionMinted(uint _position, uint _amount) public auth {
        secList[_position].minted = _amount;
    }

    function getSectionBurned(uint _position) public view returns (uint) {
        return secList[_position].burned;
    }

    function addSectionBurned(uint _amount) public auth {
        require(_amount > 0, "AddSectionBurned: amount not correct.");
        secList[burnPosition].burned = add(secList[burnPosition].burned, _amount);
    }

    function addSectionBurned(uint _position, uint _amount) public auth {
        require(_amount > 0, "AddSectionBurned: amount not correct.");
        secList[_position].burned = add(secList[_position].burned, _amount);
    }

    function setSectionBurned(uint _amount) public auth {
        secList[burnPosition].burned = _amount;
    }

    function setSectionBurned(uint _position, uint _amount) public auth {
        secList[_position].burned = _amount;
    }

    function getSectionToken(uint _position) public view returns (address[] memory) {
        return secList[_position].colIDs;
    }

    function getSectionWeight(uint _position) public view returns (uint[] memory) {
        return secList[_position].cw;
    }

    function getSectionData(uint _position) public view returns (uint, uint, uint, address[] memory, uint[] memory) {

        return (
            secList[_position].minted,
            secList[_position].burned,
            secList[_position].backupIdx,
            secList[_position].colIDs,
            secList[_position].cw
            );
    }

    function getBackupSectionData(uint _position) public view returns (uint, address[] memory, uint[] memory) {
        uint _backupIdx = getBackupSectionIndex(_position);
        return (secListBackup[_backupIdx].backupIdx, secListBackup[_backupIdx].colIDs, secListBackup[_backupIdx].cw);
    }

    function getBackupSectionIndex(uint _position) public view returns (uint) {
        return secList[_position].backupIdx;
    }

    function setBackupSectionIndex(uint _position, uint _backupIdx) public auth {
        secList[_position].backupIdx = _backupIdx;
    }
    //SWC-DoS with Failed Call: L138-L179
    function _setSection(address[] memory _wrappedTokens, uint[] memory _weight) internal {
        require(_wrappedTokens.length == _weight.length, "_SetSection: data not allow.");

        uint sum;
        uint factor = 10 ** 10;
        address[] memory _srcTokens = new address[](_weight.length);

        for (uint i = 0; i < _wrappedTokens.length; i++) {
            require(_weight[i] != 0, "_SetSection: invalid weight");
            require(_wrappedTokens[i] != address(0), "_SetSection: 0 address not allow.");
            _srcTokens[i] = IDSWrappedToken(_wrappedTokens[i]).getSrcERC20();
            require(_srcTokens[i] != address(0), "_SetSection: invalid address");
            sum = add(sum, _weight[i]);
        }

        secList.push(Section(0, 0, 0, new address[](_wrappedTokens.length), new uint[](_weight.length)));
        uint _mintPosition = secList.length - 1;

        if (_mintPosition > 0) {
            address[] memory _cruColIDs = getSectionToken(mintPosition);
            for (uint i = 0; i < _cruColIDs.length; i++)
                delete mintingTokens[_cruColIDs[i]];
        }

        for (uint i = 0; i < _wrappedTokens.length; i++) {
            require(mul(div(mul(_weight[i], factor), sum), sum) == mul(_weight[i], factor), "_SetSection: invalid weight");

            secList[_mintPosition].cw[i] = _weight[i];
            secList[_mintPosition].colIDs[i] = _wrappedTokens[i];
            mintingTokens[_wrappedTokens[i]] = true;
            wrappedTokens[_srcTokens[i]] = _wrappedTokens[i];

            if (mintedTokens[_wrappedTokens[i]])
                continue;

            mintedTokenList.push(_wrappedTokens[i]);
            mintedTokens[_wrappedTokens[i]] = true;
        }

        mintPosition = _mintPosition;
        emit UpdateSection(secList[mintPosition].colIDs, secList[mintPosition].cw);
    }

    function setSection(address[] memory _wrappedTokens, uint[] memory _weight) public auth {
        _setSection(_wrappedTokens, _weight);
    }

    function setBackupSection(uint _position, address[] memory _wrappedTokens, uint[] memory _weight) public auth {
        require(_wrappedTokens.length == _weight.length, "SetBackupSection: data not allow.");
        require(_position < mintPosition, "SetBackupSection: update mint section first.");

        uint _backupIdx = secList[_position].backupIdx;

        if (_backupIdx == 0){

            _backupIdx = backupSeed;
            secList[_position].backupIdx = _backupIdx;
            backupSeed = add(_backupIdx, 1);
        }

        secListBackup[_backupIdx] = Section(0, 0, _position, new address[](_wrappedTokens.length), new uint[](_weight.length));

        for (uint i = 0; i < _wrappedTokens.length; i++) {
            require(_wrappedTokens[i] != address(0), "SetBackupSection: token contract address invalid");
            require(_weight[i] > 0, "SetBackupSection: weight must greater than 0");

            secListBackup[_backupIdx].cw[i] = _weight[i];
            secListBackup[_backupIdx].colIDs[i] = _wrappedTokens[i];
            mintedTokens[_wrappedTokens[i]] = true;
        }
    }

    function burnSectionMoveon() public auth {
        require(
            secList[burnPosition].minted == secList[burnPosition].burned,
            "BurnSectionMoveon: burned not meet minted."
            );

        burnPosition = add(burnPosition, 1);
        assert(burnPosition <= mintPosition);
    }

    function getMintingToken(address _token) public view returns (bool) {
        return mintingTokens[_token];
    }

    function setMintingToken(address _token, bool _flag) public auth {
        mintingTokens[_token] = _flag;
    }

    function getMintedToken(address _token) public view returns (bool) {
        return mintedTokens[_token];
    }

    function setMintedToken(address _token, bool _flag) public auth {
        mintedTokens[_token] = _flag;
    }

    function getBackupToken(address _token) public view returns (address) {
        return tokenBackup[_token];
    }

    function setBackupToken(address _token, address _backupToken) public auth {
        tokenBackup[_token] = _backupToken;
    }

    function getMintedTokenList() public view returns (address[] memory) {
        return mintedTokenList;
    }

    function getMintPosition() public view returns (uint) {
        return mintPosition;
    }

    function getBurnPosition() public view returns (uint) {
        return burnPosition;
    }

    function getTotalMinted() public view returns (uint) {
        return totalMinted;
    }

    function addTotalMinted(uint _amount) public auth {
        require(_amount > 0, "AddTotalMinted: minted amount is zero.");
        totalMinted = add(totalMinted, _amount);
    }

    function setTotalMinted(uint _amount) public auth {
        totalMinted = _amount;
    }

    function getTotalBurned() public view returns (uint) {
        return totalBurned;
    }

    function addTotalBurned(uint _amount) public auth {
        require(_amount > 0, "AddTotalBurned: minted amount is zero.");
        totalBurned = add(totalBurned, _amount);
    }

    function setTotalBurned(uint _amount) public auth {
        totalBurned = _amount;
    }

    function getMinBurnAmount() public view returns (uint) {
        return minimalBurnAmount;
    }

    function setMinBurnAmount(uint _amount) public auth {
        _setMinBurnAmount(_amount);
    }

    function _setMinBurnAmount(uint _amount) internal {
        minimalBurnAmount = _amount;
    }

    function getTokenBalance(address _tokenID) public view returns (uint) {
        return poolBalance[_tokenID];
    }

    function setTokenBalance(address _tokenID, uint _amount) public auth {
        poolBalance[_tokenID] = _amount;
    }

    function getResUSDXBalance(address _tokenID) public view returns (uint) {
        return resUSDXBalance[_tokenID];
    }

    function setResUSDXBalance(address _tokenID, uint _amount) public auth {
        resUSDXBalance[_tokenID] = _amount;
    }

    function getDepositorBalance(address _depositor, address _tokenID) public view returns (uint) {
        return depositorsBalance[_depositor][_tokenID];
    }

    function setDepositorBalance(address _depositor, address _tokenID, uint _amount) public auth {
        depositorsBalance[_depositor][_tokenID] = _amount;
    }

    function setFeeRate(uint ct, uint rate) public auth {
        FeeRate[ct] = rate;
    }

    function getFeeRate(uint ct) public view returns (uint) {
        return FeeRate[ct];
    }

    function setTypeToken(uint tt, address _tokenID) public auth {
        FeeToken[tt] = _tokenID;
    }

    function getTypeToken(uint tt) public view returns (address) {
        return FeeToken[tt];
    }

    function setTokenMedian(address _tokenID, address _median) public auth {
        TokenMedian[_tokenID] = _median;
    }

    function getTokenMedian(address _tokenID) public view returns (address) {
        return TokenMedian[_tokenID];
    }

    function setTotalCol(uint _amount) public auth {
        totalCol = _amount;
    }

    function getTotalCol() public view returns (uint) {
        return totalCol;
    }

    function setWrappedToken(address _srcToken, address _wrappedToken) public auth {
        wrappedTokens[_srcToken] = _wrappedToken;
    }

    function getWrappedToken(address _srcToken) public view returns (address) {
        return  wrappedTokens[_srcToken];
    }
}
