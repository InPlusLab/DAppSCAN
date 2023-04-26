pragma solidity 0.4.25;

import "./helpers/TBoxToken.sol";
import "./helpers/ISettings.sol";
import "./helpers/IToken.sol";
import "./helpers/IOracle.sol";


/// @title TBoxManager
contract TBoxManager is TBoxToken {

    // Total packed Ether
    uint256 public globalETH;

    // Precision using for USD and commission
    uint256 public precision = 100000;

    // The address of the system settings contract
    ISettings public settings;

    /// @dev An array containing the Boxes struct for all Boxes in existence. The ID
    ///  of each Box is actually an index into this array.
    Box[] public boxes;

    /// @dev The main Box struct. Every Box in TimviSystem is represented by a copy
    ///  of this structure.
    struct Box {
        // The collateral Ether amount in wei
        uint256     collateral;
        // The number of TMV withdrawn
        uint256     tmvReleased;
    }

    /// @dev The Created event is fired whenever a new Box comes into existence. This includes
    ///  any time a Box is created through the create method.
    event Created(uint256 indexed id, address owner, uint256 collateral, uint256 tmvReleased);

    /// @dev The Closed event is fired whenever a Box is closed. Obviously, this includes
    ///  any time a Box is closed through the close method, but it is also called when
    //   a Box is closed through the closeDust method.
    event Closed(uint256 indexed id, address indexed owner, address indexed closer);

    /// @dev The Capitalized event is fired whenever a Box is capitalized.
    event Capitalized(uint256 indexed id, address indexed owner, address indexed who, uint256 tmvAmount, uint256 totalEth, uint256 userEth);

    /// @dev The EthWithdrawn event is fired whenever Ether is withdrawn from a Box
    ///  using withdrawEth method.
    event EthWithdrawn(uint256 indexed id, uint256 value, address who);

    /// @dev The TmvWithdrawn event is fired whenever TMV is withdrawn from a Box
    ///  using withdrawTmv method.
    event TmvWithdrawn(uint256 indexed id, uint256 value, address who);

    /// @dev The EthAdded event is fired whenever Ether is added to a Box
    ///  using addEth method.
    event EthAdded(uint256 indexed id, uint256 value, address who);

    /// @dev The TmvAdded event is fired whenever TMV is added to a Box
    ///  using addTmv method.
    event TmvAdded(uint256 indexed id, uint256 value, address who);

    /// @dev Defends against front-running attacks.
    modifier validTx() {
        require(tx.gasprice <= settings.gasPriceLimit(), "Gas price is greater than allowed");
        _;
    }

    /// @dev Throws if called by any account other than the owner.
    modifier onlyAdmin() {
        require(settings.isFeeManager(msg.sender), "You have no access");
        _;
    }

    /// @dev Throws if Box with specified id does not exist.
    modifier onlyExists(uint256 _id) {
        require(_exists(_id), "Box does not exist");
        _;
    }

    /// @dev Access modifier for token owner-only functionality.
    modifier onlyApprovedOrOwner(uint256 _id) {
        require(_isApprovedOrOwner(msg.sender, _id), "Box isn't your");
        _;
    }

    /// @dev The constructor sets ERC721 token name and symbol.
    /// @param _settings The address of the system settings contract.
    constructor(address _settings) TBoxToken("TBoxToken", "TBX") public {
        settings = ISettings(_settings);
    }

    /// @notice The funds are safe.
    /// @dev Creates Box with max collateral percent.
    function() external payable {
        // Redirect to the create method with no tokens to withdraw
        create(0);
    }

    /// @dev Withdraws system fee.
    function withdrawFee(address _beneficiary) external onlyAdmin {
        require(_beneficiary != address(0), "Zero address, be careful");

        // Fee is the difference between the contract balance and
        // amount of Ether used in the entire system collateralization
        uint256 _fees = address(this).balance.sub(globalETH);

        // Check that the fee is collected
        require(_fees > 0, "There is no available fees");

        // Transfer fee to provided address
        _beneficiary.transfer(_fees);
    }

    /// @dev Checks possibility of the issue of the specified token amount
    ///  for provided Ether collateral and creates new Box
    /// @param _tokensToWithdraw Number of tokens to withdraw
    /// @return New Box ID.
    function create(uint256 _tokensToWithdraw) public payable validTx returns (uint256) {
        // Check that msg.value isn't smaller than minimum deposit
        require(msg.value >= settings.minDeposit(), "Deposit is very small");

        // Calculate collateralization when tokens are needed
        if (_tokensToWithdraw > 0) {

            // The number of tokens when collateralization is high
            uint256 _tokenLimit = overCapWithdrawableTmv(msg.value);

            // The number of tokens that can be safely withdrawn from the system
            uint256 _maxGlobal = globalWithdrawableTmv(msg.value);

            // Determine the higher number of tokens
            if (_tokenLimit > _maxGlobal) {
                _tokenLimit = _maxGlobal;
            }

            // The number of tokens that can be withdrawn anyway
            uint256 _local = defaultWithdrawableTmv(msg.value);

            // Determine the higher number of tokens
            if (_tokenLimit < _local) {
                _tokenLimit = _local;
            }

            // You can only withdraw available amount
            require(_tokensToWithdraw <= _tokenLimit, "Token amount is more than available");

            // Mint TMV tokens to the Box creator
            IToken(settings.tmvAddress()).mint(msg.sender, _tokensToWithdraw);
        }

        // The id of the new Box
        uint256 _id = boxes.push(Box(msg.value, _tokensToWithdraw)).sub(1);

        // Increase global Ether counter
        globalETH = globalETH.add(msg.value);

        // Mint TBX token to the Box creator
        _mint(msg.sender, _id);

        // Fire the event
        emit Created(_id, msg.sender, msg.value, _tokensToWithdraw);

        // return the new Box's ID
        return _id;
    }

    /// @dev Allows the owner or approved user of the Box to close one by burning the
    ///  required number of tokens and return the Box's collateral.
    /// @param _id A Box ID to close.
    function close(uint256 _id) external onlyApprovedOrOwner(_id) {

        // Address of the owner of the Box
        address _owner = _tokenOwner[_id];

        // Burn needed number of tokens
        uint256 _tokensNeed = boxes[_id].tmvReleased;
        _burnTMV(msg.sender, _tokensNeed);

        // Grab a reference to the Box's collateral in storage
        uint256 _collateral = boxes[_id].collateral;

        // burn Box token
        _burn(_owner, _id);

        // Removes Box
        delete boxes[_id];

        // Send the Box's collateral to the person who made closing happen
        msg.sender.transfer(_collateral);

        // Decrease global Ether counter
        globalETH = globalETH.sub(_collateral);

        // Fire the event
        emit Closed(_id, _owner, msg.sender);
    }

    /// @notice This allows you not to be tied to the current ETH/USD rate.
    /// @dev Allows the user to capitalize a Box with the maximum current amount.
    /// @param _id A Box ID to capitalize.
    function capitalizeMax(uint256 _id) external {
        capitalize(_id, maxCapAmount(_id));
    }

    /// @dev Allows the user to capitalize a Box with specified number of tokens.
    /// @param _id A Box ID to capitalize.
    /// @param _tmv Specified number of tokens to capitalize.
    function capitalize(uint256 _id, uint256 _tmv) public validTx {

        // The maximum number of tokens for which Box can be capitalized
        uint256 _maxCapAmount = maxCapAmount(_id);

        // Check the number of tokens
        require(_tmv <= _maxCapAmount && _tmv >= 10 ** 17, "Tokens amount out of range");

        // Decrease Box TMV withdrawn counter
        boxes[_id].tmvReleased = boxes[_id].tmvReleased.sub(_tmv);

        // Calculate the Ether equivalent of tokens according to the logic
        // where 1 TMV is equal to 1 USD
        uint256 _equivalentETH = _tmv.mul(precision).div(rate());

        // Calculate system fee
        uint256 _fee = _tmv.mul(settings.sysFee()).div(rate());

        // Calculate user bonus
        uint256 _userReward = _tmv.mul(settings.userFee()).div(rate());

        // Decrease Box's collateral amount
        boxes[_id].collateral = boxes[_id].collateral.sub(_fee.add(_userReward).add(_equivalentETH));

        // Decrease global Ether counter
        globalETH = globalETH.sub(_fee.add(_userReward).add(_equivalentETH));

        // burn Box token
        _burnTMV(msg.sender, _tmv);

        // Send the Ether equivalent & user benefit to the person who made capitalization happen.
        msg.sender.transfer(_equivalentETH.add(_userReward));

        // Fire the event
        emit Capitalized(_id, ownerOf(_id), msg.sender, _tmv, _equivalentETH.add(_userReward).add(_fee), _equivalentETH.add(_userReward));
    }

    /// @notice This allows you not to be tied to the current ETH/USD rate.
    /// @dev Allows an owner or approved user of the Box to withdraw maximum amount
    ///  of Ether from the Box.
    /// @param _id A Box ID.
    function withdrawEthMax(uint256 _id) external {
        withdrawEth(_id, withdrawableEth(_id));
    }

    /// @dev Allows an owner or approved user of the Box to withdraw specified amount
    ///  of Ether from the Box.
    /// @param _id A Box ID.
    /// @param _amount The number of Ether to withdraw.
    function withdrawEth(uint256 _id, uint256 _amount) public onlyApprovedOrOwner(_id) validTx {
        require(_amount > 0, "Withdrawing zero");

        require(_amount <= withdrawableEth(_id), "You can't withdraw so much");

        // Decrease Box's collateral amount
        boxes[_id].collateral = boxes[_id].collateral.sub(_amount);

        // Decrease global Ether counter
        globalETH = globalETH.sub(_amount);

        // Send the Ether to the person who made capitalization happen
        msg.sender.transfer(_amount);

        // Fire the event
        emit EthWithdrawn(_id, _amount, msg.sender);
    }

    /// @notice This allows you not to be tied to the current ETH/USD rate.
    /// @dev Allows an owner or approved user of the Box to withdraw maximum number
    ///  of TMV tokens from the Box.
    /// @param _id A Box ID.
    function withdrawTmvMax(uint256 _id) external onlyApprovedOrOwner(_id) {
        withdrawTmv(_id, boxWithdrawableTmv(_id));
    }

    /// @dev Allows an owner or approved user of the Box to withdraw specified number
    ///  of TMV tokens from the Box.
    /// @param _id A Box ID.
    /// @param _amount The number of tokens to withdraw.
    function withdrawTmv(uint256 _id, uint256 _amount) public onlyApprovedOrOwner(_id) validTx {
        require(_amount > 0, "Withdrawing zero");

        // Check the number of tokens
        require(_amount <= boxWithdrawableTmv(_id), "You can't withdraw so much");

        // Increase Box TMV withdrawn counter
        boxes[_id].tmvReleased = boxes[_id].tmvReleased.add(_amount);

        // Mints tokens to the person who made withdrawing
        IToken(settings.tmvAddress()).mint(msg.sender, _amount);

        // Fire the event
        emit TmvWithdrawn(_id, _amount, msg.sender);
    }

    /// @dev Allows anyone to add Ether to a Box.
    /// @param _id A Box ID.
    function addEth(uint256 _id) external payable onlyExists(_id) {
        require(msg.value > 0, "Don't add 0");

        // Increase Box collateral
        boxes[_id].collateral = boxes[_id].collateral.add(msg.value);

        // Increase global Ether counter
        globalETH = globalETH.add(msg.value);

        // Fire the event
        emit EthAdded(_id, msg.value, msg.sender);
    }

    /// @dev Allows anyone to add TMV to a Box.
    /// @param _id A Box ID.
    /// @param _amount The number of tokens to add.
    function addTmv(uint256 _id, uint256 _amount) external onlyExists(_id) {
        require(_amount > 0, "Don't add 0");

        // Check the number of tokens
        require(_amount <= boxes[_id].tmvReleased, "Too much tokens");

        // Removes added tokens from the collateralization
        _burnTMV(msg.sender, _amount);
        boxes[_id].tmvReleased = boxes[_id].tmvReleased.sub(_amount);

        // Fire the event
        emit TmvAdded(_id, _amount, msg.sender);
    }

    /// @dev Allows anyone to close Box with collateral amount smaller than 3 USD.
    ///  The person who made closing happen will benefit like capitalization.
    /// @param _id A Box ID.
    function closeDust(uint256 _id) external onlyExists(_id) validTx {
        // Check collateral percent of the Box
        require(collateralPercent(_id) >= settings.minStability(), "This Box isn't collapsable");

        // Check collateral amount of the Box
        require(boxes[_id].collateral.mul(rate()) < precision.mul(3).mul(10 ** 18), "It's only possible to collapse dust");

        // Burn needed TMV amount to close
        uint256 _tmvReleased = boxes[_id].tmvReleased;
        _burnTMV(msg.sender, _tmvReleased);

        uint256 _collateral = boxes[_id].collateral;

        // Calculate the Ether equivalent of tokens according to the logic
        // where 1 TMV is equal to 1 USD
        uint256 _eth = _tmvReleased.mul(precision).div(rate());

        // Calculate user bonus
        uint256 _userReward = _tmvReleased.mul(settings.userFee()).div(rate());

        // The owner of the Box
        address _owner = ownerOf(_id);

        // Remove a Box
        delete boxes[_id];

        // Burn Box token
        _burn(_owner, _id);

        // Send the Ether equivalent & user benefit to the person who made closing happen
        msg.sender.transfer(_eth.add(_userReward));

        // Decrease global Ether counter
        globalETH = globalETH.sub(_collateral);

        // Fire the event
        emit Closed(_id, _owner, msg.sender);
    }

    /// @dev Burns specified number of TMV tokens.
    function _burnTMV(address _from, uint256 _amount) internal {
        if (_amount > 0) {
            require(IToken(settings.tmvAddress()).balanceOf(_from) >= _amount, "You don't have enough tokens");
            IToken(settings.tmvAddress()).burnLogic(_from, _amount);
        }
    }

    /// @dev Returns current oracle ETH/USD price with precision.
    function rate() public view returns(uint256) {
        return IOracle(settings.oracleAddress()).ethUsdPrice();
    }

    /// @dev Given a Box ID, returns a number of tokens that can be withdrawn.
    function boxWithdrawableTmv(uint256 _id) public view onlyExists(_id) returns(uint256) {
        Box memory box = boxes[_id];

        // Number of tokens that can be withdrawn for Box's collateral
        uint256 _amount = withdrawableTmv(box.collateral);

        if (box.tmvReleased >= _amount) {
            return 0;
        }

        // Return withdrawable rest
        return _amount.sub(box.tmvReleased);
    }

    /// @dev Given a Box ID, returns an amount of Ether that can be withdrawn.
    function withdrawableEth(uint256 _id) public view onlyExists(_id) returns(uint256) {

        // Amount of Ether that is not used in collateralization
        uint256 _avlbl = _freeEth(_id);
        // Return available Ether to withdraw
        if (_avlbl == 0) {
            return 0;
        }
        uint256 _rest = boxes[_id].collateral.sub(_avlbl);
        if (_rest < settings.minDeposit()) {
            return boxes[_id].collateral.sub(settings.minDeposit());
        }
        else return _avlbl;
    }

    /// @dev Given a Box ID, returns amount of ETH that is not used in collateralization.
    function _freeEth(uint256 _id) internal view returns(uint256) {
        // Grab a reference to the Box
        Box memory box = boxes[_id];

        // When there are no tokens withdrawn
        if (box.tmvReleased == 0) {
            return box.collateral;
        }

        // The amount of Ether that can be safely withdrawn from the system
        uint256 _maxGlobal = globalWithdrawableEth();
        uint256 _globalAvailable;

        if (_maxGlobal > 0) {
            // The amount of Ether backing the tokens when the system is overcapitalized
            uint256 _need = overCapFrozenEth(box.tmvReleased);
            if (box.collateral > _need) {
                // Free Ether amount when the system is overcapitalized
                uint256 _free = box.collateral.sub(_need);
                if (_free > _maxGlobal) {
                    // Store available amount when Box available Ether amount
                    // is more than global available
                    _globalAvailable = _maxGlobal;
                }

                // Return available amount of Ether to withdraw when the Box withdrawable
                // amount of Ether is smaller than global withdrawable amount of Ether
                else return _free;
            }
        }

        // The amount of Ether backing the tokens by default
        uint256 _frozen = defaultFrozenEth(box.tmvReleased);
        if (box.collateral > _frozen) {
            // Define the biggest number and return available Ether amount
            uint256 _localAvailable = box.collateral.sub(_frozen);
            return (_localAvailable > _globalAvailable) ? _localAvailable : _globalAvailable;
        } else {
            // Return available Ether amount
            return _globalAvailable;
        }

    }

    /// @dev Given a Box ID, returns collateral percent.
    function collateralPercent(uint256 _id) public view onlyExists(_id) returns(uint256) {
        Box memory box = boxes[_id];
        if (box.tmvReleased == 0) {
            return 10**27; //some unreachable number
        }
        uint256 _ethCollateral = box.collateral;
        // division by 100 is not necessary because to get the percent you need to multiply by 100
        return _ethCollateral.mul(rate()).div(box.tmvReleased);
    }

    /// @dev Checks if a given address currently has approval for a particular Box.
    /// @param _spender the address we are confirming Box is approved for.
    /// @param _tokenId Box ID.
    function isApprovedOrOwner(address _spender, uint256 _tokenId) external view returns (bool) {
        return _isApprovedOrOwner(_spender, _tokenId);
    }

    /// @dev Returns the global collateralization percent.
    function globalCollateralization() public view returns (uint256) {
        uint256 _supply = IToken(settings.tmvAddress()).totalSupply();
        if (_supply == 0) {
            return settings.globalTargetCollateralization();
        }
        return globalETH.mul(rate()).div(_supply);
    }

    /// @dev Returns the number of tokens that can be safely withdrawn from the system.
    function globalWithdrawableTmv(uint256 _value) public view returns (uint256) {
        uint256 _supply = IToken(settings.tmvAddress()).totalSupply();
        if (globalCollateralization() <= settings.globalTargetCollateralization()) {
            return 0;
        }
        uint256 _totalBackedTmv = defaultWithdrawableTmv(globalETH.add(_value));
        return _totalBackedTmv.sub(_supply);
    }

    /// @dev Returns Ether amount that can be safely withdrawn from the system.
    function globalWithdrawableEth() public view returns (uint256) {
        uint256 _supply = IToken(settings.tmvAddress()).totalSupply();
        if (globalCollateralization() <= settings.globalTargetCollateralization()) {
            return 0;
        }
        uint256 _need = defaultFrozenEth(_supply);
        return globalETH.sub(_need);
    }

    /// @dev Returns the number of tokens that can be withdrawn
    ///  for the specified collateral amount by default.
    function defaultWithdrawableTmv(uint256 _collateral) public view returns (uint256) {
        uint256 _num = _collateral.mul(rate());
        uint256 _div = settings.globalTargetCollateralization();
        return _num.div(_div);
    }

    /// @dev Returns the number of tokens that can be withdrawn
    ///  for the specified collateral amount when the system is overcapitalized.
    function overCapWithdrawableTmv(uint256 _collateral) public view returns (uint256) {
        uint256 _num = _collateral.mul(rate());
        uint256 _div = settings.ratio();
        return _num.div(_div);
    }

    /// @dev Returns Ether amount backing the specified number of tokens by default.
    function defaultFrozenEth(uint256 _supply) public view returns (uint256) {
        return _supply.mul(settings.globalTargetCollateralization()).div(rate());
    }


    /// @dev Returns Ether amount backing the specified number of tokens
    ///  when the system is overcapitalized.
    function overCapFrozenEth(uint256 _supply) public view returns (uint256) {
        return _supply.mul(settings.ratio()).div(rate());
    }


    /// @dev Returns the number of TMV that can capitalize the specified Box.
    function maxCapAmount(uint256 _id) public view onlyExists(_id) returns (uint256) {
        uint256 _colP = collateralPercent(_id);
        require(_colP >= settings.minStability() && _colP < settings.maxStability(), "It's only possible to capitalize toxic Boxes");

        Box memory box = boxes[_id];

        uint256 _num = box.tmvReleased.mul(settings.ratio()).sub(box.collateral.mul(rate()));
        uint256 _div = settings.ratio().sub(settings.minStability());
        return _num.div(_div);
    }

    /// @dev Returns the number of tokens that can be actually withdrawn
    ///  for the specified collateral.
    function withdrawableTmv(uint256 _collateral) public view returns(uint256) {
        uint256 _amount = overCapWithdrawableTmv(_collateral);
        uint256 _maxGlobal = globalWithdrawableTmv(0);
        if (_amount > _maxGlobal) {
            _amount = _maxGlobal;
        }
        uint256 _local = defaultWithdrawableTmv(_collateral);
        if (_amount < _local) {
            _amount = _local;
        }
        return _amount;
    }

    /// @dev Returns the collateral percentage for which tokens can be withdrawn
    ///  for the specified collateral.
    function withdrawPercent(uint256 _collateral) external view returns(uint256) {
        uint256 _amount = overCapWithdrawableTmv(_collateral);
        uint256 _maxGlobal = globalWithdrawableTmv(_collateral);
        if (_amount > _maxGlobal) {
            _amount = _maxGlobal;
        }
        uint256 _local = defaultWithdrawableTmv(_collateral);
        if (_amount < _local) {
            _amount = _local;
        }
        return _collateral.mul(rate()).div(_amount);
    }
}
