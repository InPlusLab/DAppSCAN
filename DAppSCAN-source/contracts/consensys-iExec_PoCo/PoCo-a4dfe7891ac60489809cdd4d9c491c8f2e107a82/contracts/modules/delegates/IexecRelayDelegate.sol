pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

import "../DelegateBase.sol";
import "../interfaces/IexecRelay.sol";


contract IexecRelayDelegate is IexecRelay, DelegateBase
{
	function broadcastAppOrder       (IexecLibOrders_v5.AppOrder        calldata _apporder       ) external override { emit BroadcastAppOrder       (_apporder       ); }
	function broadcastDatasetOrder   (IexecLibOrders_v5.DatasetOrder    calldata _datasetorder   ) external override { emit BroadcastDatasetOrder   (_datasetorder   ); }
	function broadcastWorkerpoolOrder(IexecLibOrders_v5.WorkerpoolOrder calldata _workerpoolorder) external override { emit BroadcastWorkerpoolOrder(_workerpoolorder); }
	function broadcastRequestOrder   (IexecLibOrders_v5.RequestOrder    calldata _requestorder   ) external override { emit BroadcastRequestOrder   (_requestorder   ); }
}
