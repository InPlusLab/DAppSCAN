pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

import "../DelegateBase.sol";
import "../interfaces/IexecOrderManagement.sol";


contract IexecOrderManagementDelegate is IexecOrderManagement, DelegateBase
{
	using IexecLibOrders_v5 for bytes32;
	using IexecLibOrders_v5 for IexecLibOrders_v5.AppOrder;
	using IexecLibOrders_v5 for IexecLibOrders_v5.DatasetOrder;
	using IexecLibOrders_v5 for IexecLibOrders_v5.WorkerpoolOrder;
	using IexecLibOrders_v5 for IexecLibOrders_v5.RequestOrder;
	using IexecLibOrders_v5 for IexecLibOrders_v5.AppOrderOperation;
	using IexecLibOrders_v5 for IexecLibOrders_v5.DatasetOrderOperation;
	using IexecLibOrders_v5 for IexecLibOrders_v5.WorkerpoolOrderOperation;
	using IexecLibOrders_v5 for IexecLibOrders_v5.RequestOrderOperation;

	/***************************************************************************
	 *                         order management tools                          *
	 ***************************************************************************/
	function manageAppOrder(IexecLibOrders_v5.AppOrderOperation memory _apporderoperation)
	public override
	{
		address owner = App(_apporderoperation.order.app).owner();
		require(owner == _msgSender() || owner == _apporderoperation.hash().toEthTypedStructHash(EIP712DOMAIN_SEPARATOR).recover(_apporderoperation.sign));

		bytes32 apporderHash = _apporderoperation.order.hash().toEthTypedStructHash(EIP712DOMAIN_SEPARATOR);
		if (_apporderoperation.operation == IexecLibOrders_v5.OrderOperationEnum.SIGN)
		{
			m_presigned[apporderHash] = owner;
			emit SignedAppOrder(apporderHash);
		}
		else if (_apporderoperation.operation == IexecLibOrders_v5.OrderOperationEnum.CLOSE)
		{
			m_consumed[apporderHash] = _apporderoperation.order.volume;
			emit ClosedAppOrder(apporderHash);
		}
	}

	function manageDatasetOrder(IexecLibOrders_v5.DatasetOrderOperation memory _datasetorderoperation)
	public override
	{
		address owner = Dataset(_datasetorderoperation.order.dataset).owner();
		require(owner == _msgSender() || owner == _datasetorderoperation.hash().toEthTypedStructHash(EIP712DOMAIN_SEPARATOR).recover(_datasetorderoperation.sign));

		bytes32 datasetorderHash = _datasetorderoperation.order.hash().toEthTypedStructHash(EIP712DOMAIN_SEPARATOR);
		if (_datasetorderoperation.operation == IexecLibOrders_v5.OrderOperationEnum.SIGN)
		{
			m_presigned[datasetorderHash] = owner;
			emit SignedDatasetOrder(datasetorderHash);
		}
		else if (_datasetorderoperation.operation == IexecLibOrders_v5.OrderOperationEnum.CLOSE)
		{
			m_consumed[datasetorderHash] = _datasetorderoperation.order.volume;
			emit ClosedDatasetOrder(datasetorderHash);
		}
	}

	function manageWorkerpoolOrder(IexecLibOrders_v5.WorkerpoolOrderOperation memory _workerpoolorderoperation)
	public override
	{
		address owner = Workerpool(_workerpoolorderoperation.order.workerpool).owner();
		require(owner == _msgSender() || owner == _workerpoolorderoperation.hash().toEthTypedStructHash(EIP712DOMAIN_SEPARATOR).recover(_workerpoolorderoperation.sign));

		bytes32 workerpoolorderHash = _workerpoolorderoperation.order.hash().toEthTypedStructHash(EIP712DOMAIN_SEPARATOR);
		if (_workerpoolorderoperation.operation == IexecLibOrders_v5.OrderOperationEnum.SIGN)
		{
			m_presigned[workerpoolorderHash] = owner;
			emit SignedWorkerpoolOrder(workerpoolorderHash);
		}
		else if (_workerpoolorderoperation.operation == IexecLibOrders_v5.OrderOperationEnum.CLOSE)
		{
			m_consumed[workerpoolorderHash] = _workerpoolorderoperation.order.volume;
			emit ClosedWorkerpoolOrder(workerpoolorderHash);
		}
	}

	function manageRequestOrder(IexecLibOrders_v5.RequestOrderOperation memory _requestorderoperation)
	public override
	{
		address owner = _requestorderoperation.order.requester;
		require(owner == _msgSender() || owner == _requestorderoperation.hash().toEthTypedStructHash(EIP712DOMAIN_SEPARATOR).recover(_requestorderoperation.sign));

		bytes32 requestorderHash = _requestorderoperation.order.hash().toEthTypedStructHash(EIP712DOMAIN_SEPARATOR);
		if (_requestorderoperation.operation == IexecLibOrders_v5.OrderOperationEnum.SIGN)
		{
			m_presigned[requestorderHash] = owner;
			emit SignedRequestOrder(requestorderHash);
		}
		else if (_requestorderoperation.operation == IexecLibOrders_v5.OrderOperationEnum.CLOSE)
		{
			m_consumed[requestorderHash] = _requestorderoperation.order.volume;
			emit ClosedRequestOrder(requestorderHash);
		}
	}
}
