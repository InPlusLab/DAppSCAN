pragma solidity >=0.4.24;

contract DummyContractV0 {
    function hello() public pure returns(string) {
        return "Konichiwa!";
    }
}

contract DummyContractV1 is DummyContractV0 {
    function hello() public pure returns(string) {
        return "Hello!";
    }

    function goodbye() public pure returns(string) {
        return "Adios";
    }
}