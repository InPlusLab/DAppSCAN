contract Trading_Charge
{
    function Amount(uint256 amount ,address to)public view returns(uint256)
    {
      uint256 charge=amount/1000;
      charge=charge*3;
      uint256 res=amount-charge;
      return res;
    }
}