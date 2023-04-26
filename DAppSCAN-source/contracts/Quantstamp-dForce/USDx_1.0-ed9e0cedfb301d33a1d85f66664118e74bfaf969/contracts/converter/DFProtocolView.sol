pragma solidity ^0.5.2;

import '../token/interfaces/IDSWrappedToken.sol';
import '../storage/interfaces/IDFStore.sol';
import '../oracle/interfaces/IMedianizer.sol';
import "../utility/DSMath.sol";

contract DFProtocolView is DSMath {
    IDFStore public dfStore;
    address public dfCol;

    constructor (address _dfStore, address _dfCol)
        public
    {
        dfStore = IDFStore(_dfStore);
        dfCol = _dfCol;
    }

    function getUSDXForDeposit(address _srcToken, uint _srcAmount) public view returns (uint) {
        address _depositor = msg.sender;
        address _tokenID = dfStore.getWrappedToken(_srcToken);
        require(dfStore.getMintingToken(_tokenID), "CalcDepositorMintTotal: asset not allow.");

        uint _amount = IDSWrappedToken(_tokenID).changeByMultiple(_srcAmount);
        uint _depositorMintTotal;
        uint _step = uint(-1);
        address[] memory _tokens;
        uint[] memory _mintCW;
        (, , , _tokens, _mintCW) = dfStore.getSectionData(dfStore.getMintPosition());

        uint[] memory _tokenBalance = new uint[](_tokens.length);
        uint[] memory _depositorBalance = new uint[](_tokens.length);
        uint[] memory _resUSDXBalance = new uint[](_tokens.length);

        for (uint i = 0; i < _tokens.length; i++) {
            _tokenBalance[i] = dfStore.getTokenBalance(_tokens[i]);
            _resUSDXBalance[i] = dfStore.getResUSDXBalance(_tokens[i]);
            _depositorBalance[i] = dfStore.getDepositorBalance(_depositor, _tokens[i]);
            if (_tokenID == _tokens[i]){
                _tokenBalance[i] = add(_tokenBalance[i], _amount);
                _depositorBalance[i] = add(_depositorBalance[i], _amount);
            }
            _step = min(div(_tokenBalance[i], _mintCW[i]), _step);
        }

        for (uint i = 0; i < _tokens.length; i++) {
            _depositorMintTotal = add(_depositorMintTotal,
                                    min(_depositorBalance[i], add(_resUSDXBalance[i], mul(_step, _mintCW[i])))
                                    );
        }

        return _depositorMintTotal;
    }

    function getUserMaxToClaim() public view returns (uint) {
        address _depositor = msg.sender;
        uint _resUSDXBalance;
        uint _depositorBalance;
        uint _depositorClaimAmount;
        uint _claimAmount;
        address[] memory _tokens = dfStore.getMintedTokenList();

        for (uint i = 0; i < _tokens.length; i++) {
            _resUSDXBalance = dfStore.getResUSDXBalance(_tokens[i]);
            _depositorBalance = dfStore.getDepositorBalance(_depositor, _tokens[i]);

            _depositorClaimAmount = min(_resUSDXBalance, _depositorBalance);
            _claimAmount = add(_claimAmount, _depositorClaimAmount);
        }

        return _claimAmount;
    }

    function getColMaxClaim() public view returns (address[] memory, uint[] memory) {
        address[] memory _tokens = dfStore.getMintedTokenList();
        uint[] memory _balance = new uint[](_tokens.length);
        address[] memory _srcTokens = new address[](_tokens.length);

        for (uint i = 0; i < _tokens.length; i++) {
            _balance[i] = dfStore.getResUSDXBalance(_tokens[i]);
            _srcTokens[i] = IDSWrappedToken(_tokens[i]).getSrcERC20();
        }

        return (_srcTokens, _balance);
    }

    function getMintingSection() public view returns(address[] memory, uint[] memory) {
        uint position = dfStore.getMintPosition();
        uint[] memory _weight = dfStore.getSectionWeight(position);
        address[] memory _tokens = dfStore.getSectionToken(position);
        address[] memory _srcTokens = new address[](_tokens.length);

        for (uint i = 0; i < _tokens.length; i++) {
            _srcTokens[i] = IDSWrappedToken(_tokens[i]).getSrcERC20();
        }

        return (_srcTokens, _weight);
    }

    function getBurningSection() public view returns(address[] memory, uint[] memory) {
        uint position = dfStore.getBurnPosition();
        uint[] memory _weight = dfStore.getSectionWeight(position);
        address[] memory _tokens = dfStore.getSectionToken(position);

        address[] memory _srcTokens = new address[](_tokens.length);

        for (uint i = 0; i < _tokens.length; i++) {
            _srcTokens[i] = IDSWrappedToken(_tokens[i]).getSrcERC20();
        }

        return (_srcTokens, _weight);
    }

    function getUserWithdrawBalance() public view returns(address[] memory, uint[] memory) {
        address _depositor = msg.sender;
        address[] memory _tokens = dfStore.getMintedTokenList();
        uint[] memory _withdrawBalances = new uint[](_tokens.length);

        address[] memory _srcTokens = new address[](_tokens.length);
        for (uint i = 0; i < _tokens.length; i++) {
            _srcTokens[i] = IDSWrappedToken(_tokens[i]).getSrcERC20();
            _withdrawBalances[i] = IDSWrappedToken(_tokens[i]).reverseByMultiple(calcWithdrawAmount(_depositor, _tokens[i]));
        }

        return (_srcTokens, _withdrawBalances);
    }

    function getPrice(uint _tokenIdx) public view returns (uint) {
        address _token = dfStore.getTypeToken(_tokenIdx);
        require(_token != address(0), "_UnifiedCommission: fee token not correct.");
        bytes32 price = IMedianizer(dfStore.getTokenMedian(_token)).read();
        return uint(price);
    }

    function getFeeRate(uint _processIdx) public view returns (uint) {
        return dfStore.getFeeRate(_processIdx);
    }

    function getDestroyThreshold() public view returns (uint) {
        return dfStore.getMinBurnAmount();
    }

    function calcWithdrawAmount(address _depositor, address _tokenID) internal view returns (uint) {
        uint _depositorBalance = dfStore.getDepositorBalance(_depositor, _tokenID);
        uint _tokenBalance = dfStore.getTokenBalance(_tokenID);
        uint _withdrawAmount = min(_tokenBalance, _depositorBalance);

        return _withdrawAmount;
    }

    function getColStatus() public view returns (address[] memory, uint[] memory) {
		address[] memory _tokens = dfStore.getMintedTokenList();
		uint[] memory _srcBalance = new uint[](_tokens.length);
		address[] memory _srcTokens = new address[](_tokens.length);
		uint _xAmount;

		for (uint i = 0; i < _tokens.length; i++) {
			_xAmount = IDSWrappedToken(_tokens[i]).balanceOf(dfCol);
			_srcBalance[i] = IDSWrappedToken(_tokens[i]).reverseByMultiple(_xAmount);
			_srcTokens[i] = IDSWrappedToken(_tokens[i]).getSrcERC20();
		}

		return (_srcTokens, _srcBalance);
    }

    function getPoolStatus() public view returns (address[] memory, uint[] memory) {
		address[] memory _tokens = dfStore.getMintedTokenList();
		uint[] memory _srcBalance = new uint[](_tokens.length);
		address[] memory _srcTokens = new address[](_tokens.length);
        uint _xAmount;

		for (uint i = 0; i < _tokens.length; i++) {
            _xAmount = dfStore.getTokenBalance(_tokens[i]);
			_srcBalance[i] = IDSWrappedToken(_tokens[i]).reverseByMultiple(_xAmount);
			_srcTokens[i] = IDSWrappedToken(_tokens[i]).getSrcERC20();
		}

		return (_srcTokens, _srcBalance);
    }

    function calcMaxMinting() public view returns(uint) {
        address[] memory _tokens;
        uint[] memory _mintCW;
        (, , , _tokens, _mintCW) = dfStore.getSectionData(dfStore.getMintPosition());

        uint _sumMintCW;
        uint _step = uint(-1);
        address _depositor = msg.sender;
        address _srcToken;
        uint _balance;
        for (uint i = 0; i < _tokens.length; i++) {
            _sumMintCW = add(_sumMintCW, _mintCW[i]);
            _srcToken = IDSWrappedToken(_tokens[i]).getSrcERC20();
            _balance = IDSWrappedToken(_srcToken).balanceOf(_depositor);
            _step = min(div(IDSWrappedToken(_tokens[i]).changeByMultiple(_balance), _mintCW[i]), _step);
        }

        return mul(_step, _sumMintCW);
    }

    function getCollateralList() public view returns (address[] memory) {
		address[] memory _tokens = dfStore.getMintedTokenList();
		address[] memory _srcTokens = new address[](_tokens.length);

		for (uint i = 0; i < _tokens.length; i++)
			_srcTokens[i] = IDSWrappedToken(_tokens[i]).getSrcERC20();

		return _srcTokens;
    }

    function getCollateralBalance(address _srcToken) public view returns (uint) {
		address _tokenID = dfStore.getWrappedToken(_srcToken);
        return IDSWrappedToken(_tokenID).reverseByMultiple(IDSWrappedToken(_tokenID).balanceOf(dfCol));
    }
}
