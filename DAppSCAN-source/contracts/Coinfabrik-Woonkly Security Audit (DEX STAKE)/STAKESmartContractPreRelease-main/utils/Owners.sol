// SPDX-License-Identifier: MIT
pragma solidity ^0.6.6;

import "./../contracts/math/SafeMath.sol";
import "./../contracts/GSN/Context.sol";


contract Owners is Context{

 using SafeMath for uint256;

    struct Sowners {
    address account;
    uint8 flag; //0 no exist  1 exist 2 deleted
    
  }


  uint256 internal _lastIndexSowners;
  mapping(uint256 => Sowners) internal _Sowners;    
  mapping(address => uint256) internal _IDSownersIndex;    
  uint256 internal _SownersCount;

 

constructor () internal {
      _lastIndexSowners = 0;
       _SownersCount = 0;
       
       address msgSender = _msgSender();
       addOwner( msgSender);
    }    



    function getOwnersCount() public view returns (uint256) {
        return _SownersCount;
    }


    function OwnerExist(address account) public view returns (bool) {
        return _SownersExist( _IDSownersIndex[account]);
    }

    function SownersIndexExist(uint256 index) internal view returns (bool) {
        
        if(_SownersCount==0) return false;
        
        if(index <  (_lastIndexSowners + 1) ) return true;
        
        return false;
    }


    function _SownersExist(uint256 SownersID)internal view returns (bool) {
        
        //0 no exist  1 exist 2 deleted
        if(_Sowners[SownersID].flag == 1 ){ 
            return true;
        }
        return false;         
    }


      modifier onlyNewOwners(address account) {
        require(!this.OwnerExist(account), "Ow:!exist");
        _;
      }
      
      
      modifier onlyOwnersExist(address account) {
        require(this.OwnerExist(account), "Ow:!exist");
        _;
      }
      
      modifier onlySownersIndexExist(uint256 index) {
        require(SownersIndexExist(index), "Ow:!iexist");
        _;
      }
  
  
      modifier onlyIsInOwners() {
        require(OwnerExist( _msgSender()) , "Own:!owners");
        _;
    }

  
  
  event addNewInOwners(address account);

function addOwner(address account) private returns(uint256){
    _lastIndexSowners=_lastIndexSowners.add(1);
    _SownersCount=  _SownersCount.add(1);
    
    _Sowners[_lastIndexSowners].account = account;
      _Sowners[_lastIndexSowners].flag = 1;
    
    _IDSownersIndex[account] = _lastIndexSowners;
    
    emit addNewInOwners(account);
    return _lastIndexSowners;
}   
     
 function newInOwners(address account ) public onlyIsInOwners onlyNewOwners(account)  returns (uint256){
     return addOwner( account);
}    




event RemovedFromOwners(address account);

function removeFromOwners(address account) public onlyIsInOwners onlyOwnersExist(account) {
    _Sowners[ _IDSownersIndex[account] ].flag = 2;
    _Sowners[ _IDSownersIndex[account] ].account=address(0);
    _SownersCount=  _SownersCount.sub(1);
    emit RemovedFromOwners( account);
}






function getOwnerByIndex(uint256 index) public view  returns( address) {
    
        if(!SownersIndexExist( index)) return address(0);
     
        Sowners memory p= _Sowners[ index ];
         
        return ( p.account);
    }



function getAllOwners() public view returns(uint256[] memory, address[] memory ) {
  
    uint256[] memory indexs=new uint256[](_SownersCount);
    address[] memory pACCs=new address[](_SownersCount);
    

    uint256 ind=0;
    
    for (uint32 i = 0; i < (_lastIndexSowners +1) ; i++) {
        Sowners memory p= _Sowners[ i ];
        if(p.flag == 1 ){
            indexs[ind]=i;
            pACCs[ind]=p.account;
            ind++;
        }
    }

    return (indexs, pACCs);

}



    
}