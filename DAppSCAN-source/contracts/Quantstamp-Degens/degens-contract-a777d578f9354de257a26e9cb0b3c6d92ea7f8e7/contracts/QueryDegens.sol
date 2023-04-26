pragma solidity ^0.5.10;

contract IERC20Token {
    function balanceOf(address tokenOwner) public view returns (uint balance);
    function allowance(address tokenOwner, address spender) public view returns (uint remaining);
    function transfer(address to, uint tokens) public returns (bool success);
    function transferFrom(address from, address to, uint tokens) public returns (bool success);
}

contract DegensInterface {
    function testOrder(uint[4] calldata packed) external view returns(uint256, uint256);
}

contract QueryDegens {
    function testOrderBatch(address degensAddress, uint[4][] memory orders) public view returns (uint[] memory, uint[] memory) {
        DegensInterface degens = DegensInterface(degensAddress);

        uint[] memory available = new uint[](orders.length);
        uint[] memory filled = new uint[](orders.length);
        
        for (uint i = 0; i < orders.length; i++) {
            (available[i], filled[i]) = degens.testOrder(orders[i]);
        }

        return (available, filled);
    }

    function tokenBalancesAndApprovals(address degensAddress, address[] memory accounts, address[] memory tokens) public view returns (uint[] memory) {
        uint[] memory output = new uint[](accounts.length * tokens.length * 2);

        uint curr = 0;
        for (uint i = 0; i < accounts.length; i++) {
            for (uint j = 0; j < tokens.length; j++) {
                output[curr++] = IERC20Token(tokens[j]).balanceOf(accounts[i]);
                output[curr++] = IERC20Token(tokens[j]).allowance(accounts[i], degensAddress);
            }
        }

        return output;
    }
}
