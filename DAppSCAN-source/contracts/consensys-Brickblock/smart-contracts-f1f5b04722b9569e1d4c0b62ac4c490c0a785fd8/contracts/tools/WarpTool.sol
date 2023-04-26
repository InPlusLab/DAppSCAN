pragma solidity ^0.4.18;


// used to change state and move block forward in testrpc
contract WarpTool {

  bool public state;

  function warp()
    public
  {
    state = !state;
  }

}
