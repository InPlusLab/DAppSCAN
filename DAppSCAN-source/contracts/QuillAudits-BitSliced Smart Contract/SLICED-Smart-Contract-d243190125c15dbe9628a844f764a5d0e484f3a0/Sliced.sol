//SPDX-License-Identifier: Unlicense
pragma solidity =0.8.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

contract Sliced is ERC20Burnable,Ownable,Pausable {

	uint public duration = 30 days; 
	
	//Multi-sig wallets
	address public community = 0x24742f95e0707714e9C9cEb909f59089709fCec8; 
	address public reward = 0x75920cfEccF81295babf2d20a0540b7479fFE3DD;
        address public marketing = 0x4d38527924f9E5d0CE071fB56B4863540aDD6113;
	address public dev = 0x0f79cFE940D2CCEfa2D8fd94Baa41E9B5e857eED;
	address public team = 0x61d14eb8b42E44402da1B02e1399bD9c01af4d59;
	address public legal = 0x96f7c22178deDFDFc1Ea421E2B105B199AbE6419;
	address public launchpad = 0xabade3a7c3a790A4Db3C106568f545aDE17A0CaC;
	
    struct Account {
		string name;
		address wallet;
		uint balancePrc;
		uint balancePrcPerRound;
		uint totalAmountclaimed;
	}

	mapping(address=>bool) public blacklistedAddresses;
	mapping(address=>bool) public admins;
	uint private lastTransferDate;
	Account[] accounts;
   
	 constructor(string memory _name, string memory _symbol,uint _supply) ERC20(_name, _symbol) {
		_initAccounts();
		uint distributedAmount = 0;
        for (uint i=0; i< 7; i++)
		{
			uint amount = (_supply*accounts[i].balancePrc)/100;
        	if(accounts[i].balancePrcPerRound>0) amount = (amount*accounts[i].balancePrcPerRound)/100;
           	distributedAmount+=amount;
		   	accounts[i].totalAmountclaimed += amount;
		   	_mint(accounts[i].wallet, amount);
		}
		lastTransferDate = block.timestamp;
		_mint(address(this), _supply-distributedAmount);

    }

    modifier isNotBlacklisted(address _from,address _to) {
      require(!blacklistedAddresses[_from], "SLICED::Sender is blacklisted");
	  require(!blacklistedAddresses[_to], "SLICED::Receiver is blacklisted");
      _;
    }
	 modifier onlyAdmin() {
	   require(admins[msg.sender], "SLICED::You Are not Admin");
      _;
    }

    function _initAccounts() internal  {
      accounts.push(Account('community',community,40,0,0));
	  accounts.push(Account('reward',reward,20,10,0));
	  accounts.push(Account('marketing',marketing,15,5,0));
	  accounts.push(Account('dev',dev,10,5,0));
	  accounts.push(Account('team',team,5,10,0));
	  accounts.push(Account('legal',legal,5,5,0));
	  accounts.push(Account('launchpad',launchpad,5,0,0));

    }
//	SWC-116-Block values as a proxy for time: L72
	function sendTokens() public onlyAdmin{
		require(block.timestamp>=lastTransferDate+duration,"SLICED::You already transfered tokens this month");
		for (uint i=0; i< 7; i++) {
				if(accounts[i].totalAmountclaimed < totalSupply()*accounts[i].balancePrc/100){
                    uint amount = ((totalSupply()*accounts[i].balancePrc/100)*accounts[i].balancePrcPerRound/100);
                    accounts[i].totalAmountclaimed+=amount;
		           _transfer(address(this),accounts[i].wallet,amount);
				}
		}
		lastTransferDate += duration;
	}
    function updateUserState(address _user,bool _state) public onlyAdmin {
		require(_user!=address(0),"SLICED::Address NULL");
        blacklistedAddresses[_user] = _state;
    }
    
	function updateAdmin(address _user,bool _state) public onlyOwner {
		require(_user!=address(0),"SLICED::Address NULL");
        admins[_user] = _state;
    }    
  
    function _beforeTokenTransfer(address _from, address _to, uint256 _amount) internal isNotBlacklisted(_from,_to) virtual  override(ERC20) {
		require(!paused(), "SLICED::Token transfer while paused");
        super._beforeTokenTransfer(_from, _to, _amount);
    }

	function pause() public  onlyOwner {
        _pause();
    }

	function unpause() public  onlyOwner {
        _unpause();
    }
}
