pragma solidity ^0.4.10;

contract ErrorPartnerSale {
    function ErrorPartnerSale() {}
}

contract PartnerSaleStub {
    function transferToPartner();
}

//a malicious crowdsale partner that could potentially call multiple times the transferToPartner function
contract ErrorPartner {
    
    bool hit;
    function ErrorPartner() {
        hit = false;
    }

    function() payable {
        PartnerSaleStub s = PartnerSaleStub(msg.sender);
        
        if(address(s) != 0x0 && !hit) {
            hit = true;
            s.transferToPartner();
        }
    }
}

//a contract that rejects any ether transfers to it
contract EtherReject {
    function EtherReject() {}
    function() payable {require(false);}
}

//can send ether via selfdestruct. that way target's fallback function is not called
contract EtherCharity {
    
    function EtherCharity() {        
    }

    function donate(address beneficiary) {
        selfdestruct(beneficiary);
    }

    function() payable {}
}


contract IToken {
    function transfer(address _to, uint256 _value) returns (bool);
    function doTransfer(address _from, address _to, uint256 _value);
}
contract ErrorTokenInternalTransfer {
    function ErrorTokenInternalTransfer() {}

    function makeLegalTransfer(address token, address to, uint256 amount) {
        (IToken(token)).transfer(to, amount);
    }

    function makeErrorTransfer(address token, address holder, uint256 amount) {
        (IToken(token)).doTransfer(holder, this, amount);
    }

}