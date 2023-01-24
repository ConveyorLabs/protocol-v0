// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "./utils/test.sol";
import "./utils/Console.sol";
import "./utils/Utils.sol";
import "../../lib/interfaces/uniswap-v2/IUniswapV2Router02.sol";
import "../../lib/interfaces/uniswap-v2/IUniswapV2Factory.sol";
import "../../lib/interfaces/token/IERC20.sol";
import "./utils/Swap.sol";
import "../../lib/interfaces/uniswap-v2/IUniswapV2Pair.sol";
import "./utils/ScriptRunner.sol";
import "../LimitOrderRouter.sol";
import "../LimitOrderQuoter.sol";
import "../ConveyorExecutor.sol";
import "../interfaces/ILimitOrderRouter.sol";
import "../interfaces/ILimitOrderBook.sol";
import "../interfaces/ISandboxLimitOrderRouter.sol";

interface CheatCodes {
    function prank(address) external;

    function expectRevert(bytes memory) external;

    function deal(address who, uint256 amount) external;

    function expectEmit(
        bool,
        bool,
        bool,
        bool
    ) external;
}

interface Errors {
    error FillAmountSpecifiedGreaterThanAmountRemaining(
        uint256 fillAmountSpecified,
        uint256 amountInRemaining,
        bytes32 orderId
    );
    error SandboxFillAmountNotSatisfied(
        bytes32 orderId,
        uint256 amountFilled,
        uint256 fillAmountRequired
    );

    error SandboxAmountOutRequiredNotSatisfied(
        bytes32 orderId,
        uint256 amountOut,
        uint256 amountOutRequired
    );
    error ConveyorFeesNotPaid(
        uint256 expectedFees,
        uint256 feesPaid,
        uint256 unpaidFeesRemaining
    );
}

contract SandboxLimitOrderRouterTest is DSTest {
    //Initialize All contract and Interface instances
    ILimitOrderRouter limitOrderRouter;
    ISandboxLimitOrderBook orderBook;
    LimitOrderExecutorWrapper limitOrderExecutor;
    LimitOrderQuoter limitOrderQuoter;
    ISandboxLimitOrderRouter sandboxRouter;
    ScriptRunner scriptRunner;
    SandboxLimitOrderBookWrapper sandboxLimitOrderBookWrapper;

    Swap swapHelper;
    Swap swapHelperUniV2;

    address uniV2Addr = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    ///@notice Initialize cheatcodes
    CheatCodes cheatCodes;

    ///@notice Test Token Address's
    address WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address LINK = 0x218532a12a389a4a92fC0C5Fb22901D1c19198aA;
    address UNI = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984;
    address USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    ///@notice Factory and router address's
    address _sushiSwapRouterAddress =
        0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;
    address _uniV2FactoryAddress = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    // address _sushiFactoryAddress = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;
    address _uniV3FactoryAddress = 0x1F98431c8aD98523631AE4a59f267346ea31F984;

    ///@notice Uniswap v2 Deployment bytescode
    bytes32 _uniswapV2HexDem =
        hex"96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f";

    ///@notice Initialize array of Dex specifications
    bytes32[] _hexDems = [_uniswapV2HexDem, _uniswapV2HexDem];
    address[] _dexFactories = [_uniV2FactoryAddress, _uniV3FactoryAddress];
    bool[] _isUniV2 = [true, false];
    uint256 SANDBOX_LIMIT_ORDER_EXECUTION_GAS_COST = 250000;
    ///@notice Fast Gwei Aggregator V3 address
    address aggregatorV3Address = 0x169E633A2D1E6c10dD91238Ba11c4A708dfEF37C;

    address payable mockOwner1 = payable(address(1));
    address payable mockOwner2 = payable(address(2));
    address payable mockOwner3 = payable(address(3));
    address payable mockOwner4 = payable(address(4));
    address payable mockOwner5 = payable(address(5));
    address payable mockOwner6 = payable(address(6));
    address payable mockOwner7 = payable(address(7));
    address payable mockOwner8 = payable(address(8));
    address payable mockOwner9 = payable(address(9));
    address payable mockOwner10 = payable(address(10));

    function setUp() public {
        scriptRunner = new ScriptRunner();
        cheatCodes = CheatCodes(HEVM_ADDRESS);
        swapHelper = new Swap(_sushiSwapRouterAddress, WETH);
        swapHelperUniV2 = new Swap(uniV2Addr, WETH);

        limitOrderQuoter = new LimitOrderQuoter(
            0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
        );

        limitOrderExecutor = new LimitOrderExecutorWrapper(
            0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
            0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48,
            address(limitOrderQuoter),
            _hexDems,
            _dexFactories,
            _isUniV2,
            1
        );

        //Wrapper contract to test internal functions
        sandboxLimitOrderBookWrapper = new SandboxLimitOrderBookWrapper(
            address(limitOrderExecutor),
            0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
            0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48,
            1
        );

        sandboxRouter = ISandboxLimitOrderRouter(
            limitOrderExecutor.SANDBOX_LIMIT_ORDER_ROUTER()
        );

        orderBook = ISandboxLimitOrderBook(
            limitOrderExecutor.SANDBOX_LIMIT_ORDER_BOOK()
        );
    }

    //================================================================
    //=========== Sandbox Integration Tests ~ SandboxLimitOrderRouter  =========
    //================================================================

    //================Single Order Execution Tests====================

    ///@notice ExecuteMulticallOrder Sandbox Router test
    function testExecuteMulticallOrderSingleV2() public {
        cheatCodes.deal(address(swapHelper), type(uint256).max);

        ///@notice Swap 1000 Ether into Dai to fund the test contract on the input token
        swapHelper.swapEthForTokenWithUniV2(1000 ether, DAI);
        ///@notice Max approve the executor on the input token.
        IERC20(DAI).approve(address(limitOrderExecutor), type(uint256).max);

        ///@notice Dai/Weth sell limit order
        ///@dev amountInRemaining 10000 DAI amountOutRemaining 1 WETH
        SandboxLimitOrderBook.SandboxLimitOrder memory order = newSandboxLimitOrder(
            false,
            100000000000000000000,
            10000000000000000, //Exact amountOutRequired.
            DAI,
            WETH
        );

        cheatCodes.prank(tx.origin);
        limitOrderExecutor.checkIn();

        dealSandboxRouterExecutionFee();

        ///@notice Initialize Arrays for Multicall struct.
        bytes32[] memory orderIds = new bytes32[](1);

        ///@notice Create a new SandboxMulticall
        SandboxLimitOrderRouter.SandboxMulticall memory multiCall;

        SandboxLimitOrderRouter.Call[]
            memory calls = new SandboxLimitOrderRouter.Call[](3);
        SandboxLimitOrderBook.SandboxLimitOrder[]
            memory orders = new SandboxLimitOrderBook.SandboxLimitOrder[](1);

        {
            address[] memory transferAddress = new address[](1);
            uint128[] memory fillAmounts = new uint128[](1);
            ///NOTE: Token0 = DAI & Token1 = WETH
            address daiWethV2 = 0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11;
            ///@notice Place the Order.
            orderIds[0] = placeMockOrder(order);
            ///@notice Grab the order fee
            orders[0] = orderBook.getSandboxLimitOrderById(orderIds[0]);
            uint256 cumulativeFee = orders[0].feeRemaining;
            ///@notice Set the DAI/WETH v2 lp address as the transferAddress.
            transferAddress[0] = daiWethV2;
            ///@notice Set the fill amount to the total amountIn on the order i.e. 10000 DAI.
            fillAmounts[0] = order.amountInRemaining;
            ///@notice Create a single v2 swap call for the multicall. Set amountOutMin to 1 WETH. And set the sandboxRouter as the receiver address.
            calls[0] = newUniV2Call(
                daiWethV2,
                0,
                10000000000000000, //Set amountOutMin to amountOutRemaining of the order
                address(sandboxRouter)
            );
            calls[1] = amountOutRequiredCompensationCall(
                _calculateExactAmountRequired(
                    fillAmounts[0],
                    order.amountInRemaining,
                    order.amountOutRemaining
                ),
                address(this),
                WETH
            );
            ///@notice Create a call to compensate the feeAmount
            calls[2] = feeCompensationCall(cumulativeFee);
            bytes32[][] memory orderIdBundles = new bytes32[][](1);
            orderIdBundles[0] = orderIds;
            multiCall = newMockMulticall(
                orderIdBundles,
                fillAmounts,
                transferAddress,
                calls
            );
        }

        {
            ///@notice Get the Cached balances pre execution

            (
                uint256 txOriginBalanceBefore,
                uint256 gasCompensationUpperBound
            ) = initializePreSandboxExecutionTxOriginGasCompensationState(
                    orderIds,
                    tx.origin
                );

            uint256 wethBalanceBefore = IERC20(WETH).balanceOf(
                address(limitOrderExecutor)
            );
            ///@notice Prank tx.origin to mock an external executor

            cheatCodes.prank(tx.origin);
            ///@notice Execute the SandboxMulticall on the sandboxRouter
            sandboxRouter.executeSandboxMulticall(multiCall);
            address[] memory owners = new address[](1);
            owners[0] = address(this);
            validatePostSandboxExecutionGasCompensation(
                txOriginBalanceBefore,
                gasCompensationUpperBound
            );
            for (uint256 i = 0; i < orders.length; ++i) {
                if (orders[i].amountInRemaining == multiCall.fillAmounts[i]) {
                    SandboxLimitOrderBook.OrderType orderType = orderBook
                        .addressToOrderIds(address(this), orders[i].orderId);
                    assert(
                        orderType ==
                            SandboxLimitOrderBook
                                .OrderType
                                .FilledSandboxLimitOrder
                    );
                }
            }
            validatePostExecutionProtocolFees(wethBalanceBefore, orders);
        }
    }

    ///@notice ExecuteMulticallOrder Sandbox Router test
    function testExecuteMulticallOrderSingleV3() public {
        cheatCodes.deal(address(swapHelper), type(uint256).max);
        cheatCodes.prank(tx.origin);
        limitOrderExecutor.checkIn();
        ///@notice Swap 1000 Ether into Dai to fund the test contract on the input token
        swapHelper.swapEthForTokenWithUniV2(1000 ether, DAI);
        ///@notice Max approve the executor on the input token.
        IERC20(DAI).approve(address(limitOrderExecutor), type(uint256).max);
        // IERC20(DAI).approve(address(sandboxRouter), type(uint256).max);
        dealSandboxRouterExecutionFee();
        ///@notice Dai/Weth sell limit order
        ///@dev amountInRemaining 1000 DAI amountOutRemaining 1 Wei
        SandboxLimitOrderBook.SandboxLimitOrder
            memory order = newSandboxLimitOrder(
                false,
                100000000000000000000,
                10000000000000000,
                DAI,
                WETH
            );
        SandboxLimitOrderRouter.SandboxMulticall memory multiCall;
        ///@notice Initialize Arrays for Multicall struct.
        bytes32[] memory orderIds = new bytes32[](1);
        SandboxLimitOrderBook.SandboxLimitOrder[]
            memory orders = new SandboxLimitOrderBook.SandboxLimitOrder[](1);
        {
            address[] memory transferAddress = new address[](1);
            uint128[] memory fillAmounts = new uint128[](1);
            SandboxLimitOrderRouter.Call[]
                memory calls = new SandboxLimitOrderRouter.Call[](3);

            ///NOTE: Token0 = DAI & Token1 = WETH
            address daiWethV3 = 0xC2e9F25Be6257c210d7Adf0D4Cd6E3E881ba25f8;
            ///@notice Place the Order.
            orderIds[0] = placeMockOrder(order);

            ///@notice Grab the order fee
            orders[0] = orderBook.getSandboxLimitOrderById(orderIds[0]);

            uint256 cumulativeFee = orders[0].feeRemaining;

            ///@notice Set the DAI/WETH v2 lp address as the transferAddress.
            transferAddress[0] = address(sandboxRouter);
            ///@notice Set the fill amount to the total amountIn on the order i.e. 1000 DAI.
            fillAmounts[0] = order.amountInRemaining;

            ///@notice Create a single v2 swap call for the multicall.
            calls[0] = newUniV3Call(
                daiWethV3,
                address(sandboxRouter),
                address(sandboxRouter),
                true,
                100000000000000000000,
                DAI
            );
            calls[1] = amountOutRequiredCompensationCall(
                _calculateExactAmountRequired(
                    fillAmounts[0],
                    order.amountInRemaining,
                    order.amountOutRemaining
                ),
                address(this),
                WETH
            );
            ///@notice Create a call to compensate the feeAmount
            calls[2] = feeCompensationCall(cumulativeFee);

            bytes32[][] memory orderIdBundles = new bytes32[][](1);
            orderIdBundles[0] = orderIds;
            multiCall = newMockMulticall(
                orderIdBundles,
                fillAmounts,
                transferAddress,
                calls
            );
        }

        {
            ///@notice Get the Cached balances pre execution

            ///@notice Get the txOrigin and GasCompensation upper bound pre execution
            (
                uint256 txOriginBalanceBefore,
                uint256 gasCompensationUpperBound
            ) = initializePreSandboxExecutionTxOriginGasCompensationState(
                    orderIds,
                    tx.origin
                );
            ///@notice Cache the executor weth balance pre execution for fee validation
            uint256 wethBalanceBefore = IERC20(WETH).balanceOf(
                address(limitOrderExecutor)
            );

            ///@notice Prank tx.origin to mock an external executor
            cheatCodes.prank(tx.origin);

            ///@notice Execute the SandboxMulticall on the sandboxRouter
            sandboxRouter.executeSandboxMulticall(multiCall);

            ///@notice Assert the Gas for execution was as expected.
            validatePostSandboxExecutionGasCompensation(
                txOriginBalanceBefore,
                gasCompensationUpperBound
            );
            for (uint256 i = 0; i < orders.length; ++i) {
                if (orders[i].amountInRemaining == multiCall.fillAmounts[i]) {
                    SandboxLimitOrderBook.OrderType orderType = orderBook
                        .addressToOrderIds(address(this), orders[i].orderId);
                    assert(
                        orderType ==
                            SandboxLimitOrderBook
                                .OrderType
                                .FilledSandboxLimitOrder
                    );
                }
            }

            ///@notice Assert the protocol fees were compensated as expected
            validatePostExecutionProtocolFees(wethBalanceBefore, orders);
        }
    }

    //================Multi Order Execution Tests====================

    ///@notice ExecuteMulticallOrder Sandbox Router test
    function testExecuteMulticallOrderBatch() public {
        cheatCodes.deal(address(swapHelper), type(uint256).max);
        cheatCodes.prank(tx.origin);
        limitOrderExecutor.checkIn();
        // IERC20(DAI).approve(address(sandboxRouter), type(uint256).max);
        dealSandboxRouterExecutionFee();

        (
            SandboxLimitOrderRouter.SandboxMulticall memory multiCall,
            SandboxLimitOrderBook.SandboxLimitOrder[] memory orders,
            bytes32[] memory orderIds
        ) = createSandboxCallMultiOrderMulticall();

        {
            ///@notice Get the txOrigin and GasCompensation upper bound pre execution
            (
                uint256 txOriginBalanceBefore,
                uint256 gasCompensationUpperBound
            ) = initializePreSandboxExecutionTxOriginGasCompensationState(
                    orderIds,
                    tx.origin
                );
            ///@notice Cache the executor weth balance pre execution for fee validation
            uint256 wethBalanceBefore = IERC20(WETH).balanceOf(
                address(limitOrderExecutor)
            );

            ///@notice Prank tx.origin to mock an external executor
            cheatCodes.prank(tx.origin);

            ///@notice Execute the SandboxMulticall on the sandboxRouter
            sandboxRouter.executeSandboxMulticall(multiCall);

            ///@notice Assert the Gas for execution was as expected.
            validatePostSandboxExecutionGasCompensation(
                txOriginBalanceBefore,
                gasCompensationUpperBound
            );

            for (uint256 i = 0; i < orders.length; ++i) {
                if (orders[i].amountInRemaining == multiCall.fillAmounts[i]) {
                    SandboxLimitOrderBook.OrderType orderType = orderBook
                        .addressToOrderIds(orders[i].owner, orders[i].orderId);

                    assert(
                        orderType ==
                            SandboxLimitOrderBook
                                .OrderType
                                .FilledSandboxLimitOrder
                    );
                } else {
                    SandboxLimitOrderBook.SandboxLimitOrder
                        memory order = orderBook.getSandboxLimitOrderById(
                            orders[i].orderId
                        );

                    assertEq(
                        order.amountInRemaining,
                        orders[i].amountInRemaining - multiCall.fillAmounts[i]
                    );

                    assertEq(
                        order.amountOutRemaining,
                        orders[i].amountOutRemaining -
                            ConveyorMath.mul64U(
                                ConveyorMath.divUU(
                                    orders[i].amountOutRemaining,
                                    orders[i].amountInRemaining
                                ),
                                multiCall.fillAmounts[i]
                            )
                    );
                }
            }

            ///@notice Assert the protocol fees were compensated as expected
            validatePostExecutionProtocolFees(wethBalanceBefore, orders);
        }
    }

    ///@notice ExecuteMulticallOrder Sandbox Router test
    function testExecuteMulticallOrdersSameOwnerBundleInputToken() public {
        cheatCodes.deal(address(swapHelper), type(uint256).max);
        cheatCodes.prank(tx.origin);
        limitOrderExecutor.checkIn();
        ///@notice Swap 1000 Ether into Dai to fund the test contract on the input token
        swapHelper.swapEthForTokenWithUniV2(1000 ether, DAI);
        ///@notice Max approve the executor on the input token.
        IERC20(DAI).approve(address(limitOrderExecutor), type(uint256).max);
        // IERC20(DAI).approve(address(sandboxRouter), type(uint256).max);
        dealSandboxRouterExecutionFee();

        SandboxLimitOrderRouter.SandboxMulticall memory multiCall;
        ///@notice Initialize Arrays for Multicall struct.

        SandboxLimitOrderBook.SandboxLimitOrder[]
            memory orders = createMockOrdersSameInputToken();

        ///@notice Place the Order.
        bytes32[] memory orderIds = placeMultipleMockOrder(orders);
        {
            address[] memory transferAddress = new address[](2);
            uint128[] memory fillAmounts = new uint128[](2);
            SandboxLimitOrderRouter.Call[]
                memory calls = new SandboxLimitOrderRouter.Call[](3);

            ///NOTE: Token0 = DAI & Token1 = WETH
            address daiWethV3 = 0xC2e9F25Be6257c210d7Adf0D4Cd6E3E881ba25f8;

            console.logBytes32(orderIds[0]);
            console.logBytes32(orderIds[1]);

            ///@notice Grab the order fee
            orders[0] = orderBook.getSandboxLimitOrderById(orderIds[0]);
            orders[1] = orderBook.getSandboxLimitOrderById(orderIds[1]);

            console.log(orders[0].owner);
            console.log(orders[1].owner);

            uint256 cumulativeFee = orders[0].feeRemaining +
                orders[1].feeRemaining;

            ///@notice Set the DAI/WETH v2 lp address as the transferAddress.
            transferAddress[0] = address(sandboxRouter);
            transferAddress[1] = address(sandboxRouter);

            ///@notice Set the fill amount to the total amountIn on the order i.e. 1000 DAI.
            fillAmounts[0] = orders[0].amountInRemaining;
            fillAmounts[1] = orders[1].amountInRemaining;

            ///@notice Create a single v2 swap call for the multicall.
            calls[0] = newUniV3Call(
                daiWethV3,
                address(sandboxRouter),
                address(sandboxRouter),
                true,
                200000000000000000000,
                DAI
            );

            calls[1] = amountOutRequiredCompensationCall(
                _calculateExactAmountRequired(
                    fillAmounts[0],
                    orders[0].amountInRemaining,
                    orders[0].amountOutRemaining
                ),
                address(this),
                WETH
            );

            calls[2] = amountOutRequiredCompensationCall(
                _calculateExactAmountRequired(
                    fillAmounts[1],
                    orders[1].amountInRemaining,
                    orders[1].amountOutRemaining
                ),
                address(this),
                WETH
            );

            ///@notice Create a call to compensate the feeAmount
            calls[1] = feeCompensationCall(cumulativeFee);
            bytes32[][]
                memory orderIdBundles = initialize2DimensionalOrderIdBundlesArray();
            ///@notice If the owner address is the same and the input/output token is the same.
            ///The orderIds must be adjacent in the orderIdBundles array so the contract can do proper
            ///Validation on the tokenBalances vs the fillAmounts and amountOutRequired
            orderIdBundles[0][0] = orderIds[0];
            orderIdBundles[0][1] = orderIds[1];
            multiCall = newMockMulticall(
                orderIdBundles,
                fillAmounts,
                transferAddress,
                calls
            );
        }

        {
            ///@notice Get the Cached balances pre execution

            ///@notice Get the txOrigin and GasCompensation upper bound pre execution
            (
                uint256 txOriginBalanceBefore,
                uint256 gasCompensationUpperBound
            ) = initializePreSandboxExecutionTxOriginGasCompensationState(
                    orderIds,
                    tx.origin
                );
            ///@notice Cache the executor weth balance pre execution for fee validation
            uint256 wethBalanceBefore = IERC20(WETH).balanceOf(
                address(limitOrderExecutor)
            );

            ///@notice Prank tx.origin to mock an external executor
            cheatCodes.prank(tx.origin);

            ///@notice Execute the SandboxMulticall on the sandboxRouter
            sandboxRouter.executeSandboxMulticall(multiCall);

            ///@notice Assert the Gas for execution was as expected.
            validatePostSandboxExecutionGasCompensation(
                txOriginBalanceBefore,
                gasCompensationUpperBound
            );

            for (uint256 i = 0; i < orders.length; ++i) {
                SandboxLimitOrderBook.OrderType orderType = orderBook
                    .addressToOrderIds(address(this), orderIds[i]);
                assert(
                    orderType ==
                        SandboxLimitOrderBook.OrderType.FilledSandboxLimitOrder
                );
            }

            ///@notice Assert the protocol fees were compensated as expected
            validatePostExecutionProtocolFees(wethBalanceBefore, orders);
        }
    }

    function testFailExecuteMulticallOrder_ExecutorNotCheckedIn() public {
        SandboxLimitOrderRouter.SandboxMulticall memory multiCall;
        ///Should revert because the executor is not checked in
        sandboxRouter.executeSandboxMulticall(multiCall);
    }

    function createMockOrdersSameInputToken()
        internal
        view
        returns (SandboxLimitOrderBook.SandboxLimitOrder[] memory orders)
    {
        ///@notice Dai/Weth sell limit order
        ///@dev amountInRemaining 1000 DAI amountOutRemaining 1 Wei
        SandboxLimitOrderBook.SandboxLimitOrder
            memory order0 = newSandboxLimitOrder(
                false,
                100000000000000000000,
                10000000000000000,
                DAI,
                WETH
            );
        ///@notice Dai/Weth sell limit order
        ///@dev amountInRemaining 1000 DAI amountOutRemaining 1 Wei
        SandboxLimitOrderBook.SandboxLimitOrder
            memory order1 = newSandboxLimitOrder(
                false,
                100000000000000000000,
                10000000000000000,
                DAI,
                WETH
            );

        orders = new SandboxLimitOrderBook.SandboxLimitOrder[](2);
        orders[0] = order0;
        orders[1] = order1;
    }

    function initialize2DimensionalOrderIdBundlesArray()
        internal
        pure
        returns (bytes32[][] memory)
    {
        bytes32[][] memory orderIdBundles = new bytes32[][](1);

        for (uint256 i = 0; i < orderIdBundles.length; ++i) {
            orderIdBundles[i] = new bytes32[](2);
        }
        return orderIdBundles;
    }

    //================Execution Fail Case Tests====================
    function testFailExecuteMulticallOrder_FillAmountSpecifiedGreaterThanAmountRemaining()
        public
    {
        cheatCodes.deal(address(swapHelper), type(uint256).max);

        ///@notice Swap 1000 Ether into Dai to fund the test contract on the input token
        swapHelper.swapEthForTokenWithUniV2(1000 ether, DAI);
        ///@notice Max approve the executor on the input token.
        IERC20(DAI).approve(address(limitOrderExecutor), type(uint256).max);

        ///@notice Dai/Weth sell limit order
        ///@dev amountInRemaining 1000 DAI amountOutRemaining 1 Wei
        SandboxLimitOrderBook.SandboxLimitOrder
            memory order = newSandboxLimitOrder(
                false,
                10000000000000000000,
                1,
                DAI,
                WETH
            );

        dealSandboxRouterExecutionFee();
        ///@notice Initialize Arrays for Multicall struct.
        bytes32[] memory orderIds = new bytes32[](1);

        ///@notice Create a new SandboxMulticall
        SandboxLimitOrderRouter.SandboxMulticall memory multiCall;

        SandboxLimitOrderRouter.Call[]
            memory calls = new SandboxLimitOrderRouter.Call[](2);
        SandboxLimitOrderBook.SandboxLimitOrder[]
            memory orders = new SandboxLimitOrderBook.SandboxLimitOrder[](1);
        {
            address[] memory transferAddress = new address[](1);
            uint128[] memory fillAmounts = new uint128[](1);
            ///NOTE: Token0 = DAI & Token1 = WETH
            address daiWethV2 = 0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11;
            ///@notice Place the Order.
            orderIds[0] = placeMockOrder(order);
            ///@notice Grab the order fee
            orders[0] = orderBook.getSandboxLimitOrderById(orderIds[0]);
            uint256 cumulativeFee = orders[0].feeRemaining;
            ///@notice Set the DAI/WETH v2 lp address as the transferAddress.
            transferAddress[0] = daiWethV2;

            fillAmounts[0] = order.amountInRemaining + 1; //Set fill amount to more than the amountInRemaining
            ///@notice Create a single v2 swap call for the multicall.
            calls[0] = newUniV2Call(daiWethV2, 0, 100, address(this));
            ///@notice Create a call to compensate the feeAmount
            calls[1] = feeCompensationCall(cumulativeFee);
            bytes32[][] memory orderIdBundles = new bytes32[][](1);
            orderIdBundles[0] = orderIds;
            multiCall = newMockMulticall(
                orderIdBundles,
                fillAmounts,
                transferAddress,
                calls
            );
        }

        ///@notice Prank tx.origin to mock an external executor
        cheatCodes.prank(tx.origin);

        ///@notice Execute the SandboxMulticall on the sandboxRouter
        sandboxRouter.executeSandboxMulticall(multiCall);
    }

    function testFailExecuteMulticallOrder_SandboxAmountOutRequiredNotSatisfied()
        public
    {
        cheatCodes.deal(address(swapHelper), type(uint256).max);

        ///@notice Swap 1000 Ether into Dai to fund the test contract on the input token
        swapHelper.swapEthForTokenWithUniV2(1000 ether, DAI);
        ///@notice Max approve the executor on the input token.
        IERC20(DAI).approve(address(limitOrderExecutor), type(uint256).max);

        ///@notice Dai/Weth sell limit order
        ///@dev amountInRemaining 1000 DAI amountOutRemaining 1 Wei
        SandboxLimitOrderBook.SandboxLimitOrder
            memory order = newSandboxLimitOrder(
                false,
                10000000000000000000,
                100000000000000000,
                DAI,
                WETH
            );

        dealSandboxRouterExecutionFee();
        ///@notice Initialize Arrays for Multicall struct.
        bytes32[] memory orderIds = new bytes32[](1);

        ///@notice Create a new SandboxMulticall
        SandboxLimitOrderRouter.SandboxMulticall memory multiCall;

        SandboxLimitOrderRouter.Call[]
            memory calls = new SandboxLimitOrderRouter.Call[](2);
        SandboxLimitOrderBook.SandboxLimitOrder[]
            memory orders = new SandboxLimitOrderBook.SandboxLimitOrder[](1);
        {
            address[] memory transferAddress = new address[](1);
            uint128[] memory fillAmounts = new uint128[](1);
            ///NOTE: Token0 = DAI & Token1 = WETH
            address daiWethV2 = 0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11;
            ///@notice Place the Order.
            orderIds[0] = placeMockOrder(order);
            ///@notice Grab the order fee
            orders[0] = orderBook.getSandboxLimitOrderById(orderIds[0]);
            uint256 cumulativeFee = orders[0].feeRemaining;
            ///@notice Set the DAI/WETH v2 lp address as the transferAddress.
            transferAddress[0] = daiWethV2;

            fillAmounts[0] = order.amountInRemaining;
            ///@notice Create a single v2 swap call for the multicall.
            //AmountOutMin set to 1 which won't cover the amountOutRemaining
            calls[0] = newUniV2Call(daiWethV2, 0, 1, address(this));
            ///@notice Create a call to compensate the feeAmount
            calls[1] = feeCompensationCall(cumulativeFee);
            bytes32[][] memory orderIdBundles = new bytes32[][](1);
            orderIdBundles[0] = orderIds;
            multiCall = newMockMulticall(
                orderIdBundles,
                fillAmounts,
                transferAddress,
                calls
            );
        }

        ///@notice Prank tx.origin to mock an external executor
        cheatCodes.prank(tx.origin);

        ///@notice Execute the SandboxMulticall on the sandboxRouter
        sandboxRouter.executeSandboxMulticall(multiCall);
    }

    function testFailExecuteMulticallOrder_ConveyorFeesNotPaid() public {
        cheatCodes.deal(address(swapHelper), type(uint256).max);

        ///@notice Swap 1000 Ether into Dai to fund the test contract on the input token
        swapHelper.swapEthForTokenWithUniV2(1000 ether, DAI);
        ///@notice Max approve the executor on the input token.
        IERC20(DAI).approve(address(limitOrderExecutor), type(uint256).max);

        ///@notice Dai/Weth sell limit order
        ///@dev amountInRemaining 1000 DAI amountOutRemaining 1 Wei
        SandboxLimitOrderBook.SandboxLimitOrder
            memory order = newSandboxLimitOrder(
                false,
                10000000000000000000,
                1,
                DAI,
                WETH
            );

        dealSandboxRouterExecutionFee();
        ///@notice Initialize Arrays for Multicall struct.
        bytes32[] memory orderIds = new bytes32[](1);

        ///@notice Create a new SandboxMulticall
        SandboxLimitOrderRouter.SandboxMulticall memory multiCall;

        SandboxLimitOrderRouter.Call[]
            memory calls = new SandboxLimitOrderRouter.Call[](2);
        SandboxLimitOrderBook.SandboxLimitOrder[]
            memory orders = new SandboxLimitOrderBook.SandboxLimitOrder[](1);
        {
            address[] memory transferAddress = new address[](1);
            uint128[] memory fillAmounts = new uint128[](1);
            ///NOTE: Token0 = DAI & Token1 = WETH
            address daiWethV2 = 0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11;
            ///@notice Place the Order.
            orderIds[0] = placeMockOrder(order);
            ///@notice Grab the order fee
            orders[0] = orderBook.getSandboxLimitOrderById(orderIds[0]);
            uint256 cumulativeFee = 0; //Dont pay a fee should revert on ConveyorFeesNotPaid
            ///@notice Set the DAI/WETH v2 lp address as the transferAddress.
            transferAddress[0] = daiWethV2;

            fillAmounts[0] = order.amountInRemaining;
            ///@notice Create a single v2 swap call for the multicall.
            //AmountOutMin set to 1 which won't cover the amountOutRemaining
            calls[0] = newUniV2Call(daiWethV2, 0, 1, address(this));
            ///@notice Create a call to compensate the feeAmount
            calls[1] = feeCompensationCall(cumulativeFee);
            bytes32[][] memory orderIdBundles = new bytes32[][](1);
            orderIdBundles[0] = orderIds;
            multiCall = newMockMulticall(
                orderIdBundles,
                fillAmounts,
                transferAddress,
                calls
            );
        }

        ///@notice Prank tx.origin to mock an external executor
        cheatCodes.prank(tx.origin);

        ///@notice Execute the SandboxMulticall on the sandboxRouter
        sandboxRouter.executeSandboxMulticall(multiCall);
    }

    function testFailExecuteMulticallOrder_InvalidTransferAddressArray()
        public
    {
        cheatCodes.deal(address(swapHelper), type(uint256).max);

        ///@notice Swap 1000 Ether into Dai to fund the test contract on the input token
        swapHelper.swapEthForTokenWithUniV2(1000 ether, DAI);
        ///@notice Max approve the executor on the input token.
        IERC20(DAI).approve(address(limitOrderExecutor), type(uint256).max);

        ///@notice Dai/Weth sell limit order
        ///@dev amountInRemaining 1000 DAI amountOutRemaining 1 Wei
        SandboxLimitOrderBook.SandboxLimitOrder
            memory order = newSandboxLimitOrder(
                false,
                10000000000000000000,
                1,
                DAI,
                WETH
            );

        dealSandboxRouterExecutionFee();
        ///@notice Initialize Arrays for Multicall struct.
        bytes32[] memory orderIds = new bytes32[](1);

        ///@notice Create a new SandboxMulticall
        SandboxLimitOrderRouter.SandboxMulticall memory multiCall;

        SandboxLimitOrderRouter.Call[]
            memory calls = new SandboxLimitOrderRouter.Call[](2);
        SandboxLimitOrderBook.SandboxLimitOrder[]
            memory orders = new SandboxLimitOrderBook.SandboxLimitOrder[](1);

        {
            address[] memory transferAddress = new address[](2); //Set transfer addresses to a different size than orderIds, should revert on InvalidTransferAddressArray
            uint128[] memory fillAmounts = new uint128[](1);
            ///NOTE: Token0 = DAI & Token1 = WETH
            address daiWethV2 = 0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11;
            ///@notice Place the Order.
            orderIds[0] = placeMockOrder(order);
            ///@notice Grab the order fee
            orders[0] = orderBook.getSandboxLimitOrderById(orderIds[0]);
            uint256 cumulativeFee = orders[0].feeRemaining; //Dont pay a fee should revert on ConveyorFeesNotPaid
            ///@notice Set the DAI/WETH v2 lp address as the transferAddress.
            transferAddress[0] = daiWethV2;

            fillAmounts[0] = order.amountInRemaining;
            ///@notice Create a single v2 swap call for the multicall.
            //AmountOutMin set to 1 which won't cover the amountOutRemaining
            calls[0] = newUniV2Call(daiWethV2, 0, 1, address(this));
            ///@notice Create a call to compensate the feeAmount
            calls[1] = feeCompensationCall(cumulativeFee);
            bytes32[][] memory orderIdBundles = new bytes32[][](1);
            orderIdBundles[0] = orderIds;
            multiCall = newMockMulticall(
                orderIdBundles,
                fillAmounts,
                transferAddress,
                calls
            );
        }

        ///@notice Prank tx.origin to mock an external executor
        cheatCodes.prank(tx.origin);

        ///@notice Execute the SandboxMulticall on the sandboxRouter
        sandboxRouter.executeSandboxMulticall(multiCall);
    }

    //================================================================
    //====== Sandbox Execution Unit Tests ~ LimitOrderRouter =========
    //================================================================

    function testInitializeSandboxExecutionState(
        uint128 wethQuantity,
        uint128 fillAmountWeth
    ) public {
        bool run;
        uint256 minWethQuantity = 10e15;
        assembly {
            run := and(
                lt(minWethQuantity, wethQuantity),
                lt(wethQuantity, 10000000000000000000000)
            )
        }
        if (run) {
            cheatCodes.deal(address(swapHelper), type(uint128).max);

            cheatCodes.deal(address(this), wethQuantity);

            ///@notice Wrap the weth to send from the sandboxRouter to the executor in a call.
            (bool depositSuccess, ) = address(WETH).call{value: wethQuantity}(
                abi.encodeWithSignature("deposit()")
            );
            require(depositSuccess, "Fudge");
            IERC20(WETH).approve(address(limitOrderExecutor), wethQuantity);

            ///@notice Dai/Weth sell limit order
            ///@dev amountInRemaining 1000 DAI amountOutRemaining 1 Wei
            SandboxLimitOrderBook.SandboxLimitOrder
                memory orderWeth = newSandboxLimitOrder(
                    false,
                    wethQuantity,
                    1,
                    WETH,
                    DAI
                );

            bytes32[] memory orderIds = new bytes32[](1);
            uint128[] memory fillAmounts = new uint128[](1);
            bytes32[][] memory orderIdBundles = new bytes32[][](1);
            {
                orderIds[0] = placeMockOrderWrapper(orderWeth);
                orderIdBundles[0] = orderIds;

                fillAmounts[0] = fillAmountWeth;
            }

            {
                if (fillAmountWeth > wethQuantity) {
                    cheatCodes.expectRevert(
                        abi.encodeWithSelector(
                            Errors
                                .FillAmountSpecifiedGreaterThanAmountRemaining
                                .selector,
                            fillAmountWeth,
                            wethQuantity,
                            orderIds[0]
                        )
                    );
                    (bool reverted, ) = address(sandboxLimitOrderBookWrapper)
                        .call(
                            abi.encodeWithSignature(
                                "initializePreSandboxExecutionState(bytes32[][],uint128[])",
                                orderIdBundles,
                                fillAmounts
                            )
                        );
                    assertTrue(reverted);
                } else {
                    SandboxLimitOrderBook.PreSandboxExecutionState
                        memory preSandboxExecutionState = sandboxLimitOrderBookWrapper
                            .initializePreSandboxExecutionState(
                                orderIdBundles,
                                fillAmounts
                            );

                    assertEq(
                        preSandboxExecutionState.initialTokenInBalances[0],
                        wethQuantity
                    );
                    assertEq(
                        preSandboxExecutionState.initialTokenOutBalances[0],
                        0
                    );
                }
            }
        }
    }

    function testValidateSandboxExecutionAndFillOrders(
        uint128 wethQuantity,
        uint128 initialBalanceIn,
        uint128 daiQuantity,
        uint128 amountOutRemaining,
        uint128 fillAmountWeth
    ) public {
        bool run;
        {
            if (
                wethQuantity < 1000000000000000 ||
                daiQuantity < 1000000000000000 ||
                wethQuantity > 10000000000000000000000 ||
                daiQuantity > 10000000000000000000000
            ) {
                run = false;
            }
        }
        if (run) {
            if (
                fillAmountWeth <= wethQuantity &&
                initialBalanceIn < wethQuantity
            ) {
                initializeTestBalanceState(wethQuantity);

                uint256[] memory initialBalancesIn = new uint256[](1);
                uint256[] memory initialBalancesOut = new uint256[](1);

                {
                    initialBalancesIn[0] = initialBalanceIn;
                    initialBalancesOut[0] = 0;
                }
                ///@notice Swap 1000 Ether into Dai to fund the test contract on the input token
                try
                    swapHelper.swapEthForTokenWithUniV2(daiQuantity, DAI)
                returns (uint256 amountOut) {
                    {}
                    SandboxLimitOrderBook.SandboxLimitOrder[]
                        memory orders = new SandboxLimitOrderBook.SandboxLimitOrder[](
                            1
                        );

                    uint128[] memory fillAmounts = new uint128[](2);
                    bytes32[][] memory orderIdBundles = new bytes32[][](1);
                    {
                        ///@notice Dai/Weth sell limit order
                        ///@dev amountInRemaining 1000 DAI amountOutRemaining 1 Wei
                        orders[0] = newSandboxLimitOrder(
                            false,
                            wethQuantity,
                            amountOutRemaining,
                            WETH,
                            DAI
                        );

                        bytes32[] memory orderIds = new bytes32[](1);
                        orderIds[0] = placeMockOrderWrapper(orders[0]);
                        fillAmounts[0] = fillAmountWeth;
                        orderIdBundles[0] = orderIds;
                    }

                    validateSandboxExecutionAndFillOrders(
                        orderIdBundles,
                        initialBalancesIn,
                        initialBalancesOut,
                        wethQuantity,
                        orders,
                        fillAmounts,
                        amountOut
                    );
                } catch {}
            }
        }
    }

    function validateSandboxExecutionAndFillOrders(
        bytes32[][] memory orderIdBundles,
        uint256[] memory initialBalancesIn,
        uint256[] memory initialBalancesOut,
        uint256 wethQuantity,
        SandboxLimitOrderBook.SandboxLimitOrder[] memory orders,
        uint128[] memory fillAmounts,
        uint256 amountOut
    ) internal {
        SandboxLimitOrderBook.PreSandboxExecutionState
            memory preSandboxExecutionState = SandboxLimitOrderBook
                .PreSandboxExecutionState({
                    sandboxLimitOrders: orders,
                    orderOwners: new address[](orders.length),
                    initialTokenInBalances: initialBalancesIn,
                    initialTokenOutBalances: initialBalancesOut
                });
        if (
            initialBalancesIn[0] - wethQuantity > fillAmounts[0] ||
            amountOut < orders[0].amountOutRemaining
        ) {
            cheatCodes.expectRevert(
                abi.encodeWithSelector(
                    initialBalancesIn[0] - wethQuantity > fillAmounts[0]
                        ? Errors.SandboxFillAmountNotSatisfied.selector
                        : Errors.SandboxAmountOutRequiredNotSatisfied.selector,
                    orders[0].orderId,
                    initialBalancesIn[0] - wethQuantity > fillAmounts[0]
                        ? initialBalancesIn[0] - wethQuantity
                        : amountOut,
                    initialBalancesIn[0] - wethQuantity > fillAmounts[0]
                        ? fillAmounts[0]
                        : ConveyorMath.mul64U(
                            ConveyorMath.divUU(
                                orders[0].amountOutRemaining,
                                orders[0].amountInRemaining
                            ),
                            fillAmounts[0]
                        )
                )
            );

            (bool status, ) = address(sandboxLimitOrderBookWrapper).call(
                abi.encodeWithSignature(
                    "validateSandboxExecutionAndFillOrders(bytes32[][],uint128[],LimitOrderRouter.PreSandboxExecutionState)",
                    orderIdBundles,
                    fillAmounts,
                    preSandboxExecutionState
                )
            );
            assertTrue(status);
        } else {
            sandboxLimitOrderBookWrapper.validateSandboxExecutionAndFillOrders(
                orderIdBundles,
                fillAmounts,
                preSandboxExecutionState
            );
            {
                SandboxLimitOrderBook.SandboxLimitOrder
                    memory postExecutionOrder = sandboxLimitOrderBookWrapper
                        ._getSandboxLimitOrderById(orders[0].orderId);
                if (fillAmounts[0] == orders[0].amountInRemaining) {
                    assert(postExecutionOrder.orderId == bytes32(0));
                } else {
                    ///@notice Assert the amountInRemaining is reduced by the fillAmount
                    assertEq(
                        postExecutionOrder.amountInRemaining,
                        orders[0].amountInRemaining - fillAmounts[0]
                    );
                    ///@notice Assert the amountOutRemaining is reduced by the fillAmount*amountOutRemaining/amountInRemaining.
                    assertEq(
                        postExecutionOrder.amountOutRemaining,
                        ConveyorMath.mul64U(
                            ConveyorMath.divUU(
                                orders[0].amountOutRemaining,
                                orders[0].amountInRemaining
                            ),
                            fillAmounts[0]
                        )
                    );
                    ///@notice Assert the feeRemaining is reduced by the feeRemaining*fillAmount/amountInRemaining.
                    assertEq(
                        postExecutionOrder.feeRemaining,
                        ConveyorMath.mul64U(
                            ConveyorMath.divUU(
                                fillAmounts[0],
                                orders[0].amountInRemaining
                            ),
                            orders[0].feeRemaining
                        )
                    );
                }
            }
        }
    }

    //================================================================
    //====== Sandbox Execution Unit Tests ~ ConveyorExecutor =======
    //================================================================
    function _requireConveyorFeeIsPaid(
        uint128 contractBalancePreExecution,
        uint128 expectedAccumulatedFees,
        uint128 compensationAmount
    ) public {
        cheatCodes.deal(address(limitOrderExecutor), compensationAmount);
        cheatCodes.prank(address(limitOrderExecutor));
        ///@notice Wrap the weth to send from the sandboxRouter to the executor in a call.
        (bool depositSuccess, ) = address(WETH).call{value: compensationAmount}(
            abi.encodeWithSignature("deposit()")
        );
        require(depositSuccess, "Fudge");

        if (
            contractBalancePreExecution + expectedAccumulatedFees >
            compensationAmount
        ) {
            cheatCodes.expectRevert(
                abi.encodeWithSelector(
                    Errors.ConveyorFeesNotPaid.selector,
                    expectedAccumulatedFees,
                    IERC20(WETH).balanceOf(address(limitOrderExecutor)) -
                        contractBalancePreExecution,
                    expectedAccumulatedFees -
                        ((compensationAmount + contractBalancePreExecution) -
                            contractBalancePreExecution)
                )
            );
            (bool reverted, ) = address(limitOrderExecutor).call(
                abi.encodeWithSignature(
                    "requireConveyorFeeIsPaid(uint256, uint256)",
                    uint256(contractBalancePreExecution),
                    uint256(expectedAccumulatedFees)
                )
            );
            contractBalancePreExecution + expectedAccumulatedFees >
                compensationAmount
                ? assertTrue(reverted)
                : assertTrue(!reverted);
        }
    }

    //================================================================
    //=========== Sandbox Execution State Assertion Helpers ==========
    //================================================================

    ///@notice Helper to get the txOrigin balance and upper limit on gas compensation prior to execution
    function initializePreSandboxExecutionTxOriginGasCompensationState(
        bytes32[] memory orderIds,
        address txOrigin
    )
        internal
        view
        returns (
            uint256 txOriginBalanceBefore,
            uint256 gasCompensationUpperBound
        )
    {
        txOriginBalanceBefore = address(txOrigin).balance;
        for (uint256 i = 0; i < orderIds.length; ++i) {
            SandboxLimitOrderBook.SandboxLimitOrder memory order = orderBook
                .getSandboxLimitOrderById(orderIds[i]);
            gasCompensationUpperBound += order.executionCreditRemaining;
            ///@notice The order has been placed so it should have an orderId
            assert(order.orderId != bytes32(0));
        }
    }

    function validatePostSandboxExecutionGasCompensation(
        uint256 txOriginBalanceBefore,
        uint256 gasCompensationUpperBound
    ) internal {
        ///@notice The ETH balance of tx.origin - txOriginBalanceBefore is the total amount of gas credits compensated to the beacon for execution.
        uint256 totalGasCompensated = address(tx.origin).balance -
            txOriginBalanceBefore;

        ///@notice Ensure the totalGasCompensation didn't exceed the upper bound.
        assertLe(totalGasCompensated, gasCompensationUpperBound);
    }

    function validatePostExecutionProtocolFees(
        uint256 wethBalanceBefore,
        SandboxLimitOrderBook.SandboxLimitOrder[] memory orders
    ) internal {
        uint256 totalOrderFees = 0;
        for (uint256 i = 0; i < orders.length; ++i) {
            totalOrderFees += orders[i].feeRemaining;
        }
        uint256 feesCompensated = IERC20(WETH).balanceOf(
            address(limitOrderExecutor)
        ) - wethBalanceBefore;
        assertEq(feesCompensated, totalOrderFees);
    }

    //================================================================
    //====================== Misc Helpers ============================
    //================================================================
    function initializeTestBalanceState(uint128 wethQuantity) internal {
        cheatCodes.deal(address(swapHelper), type(uint128).max);
        cheatCodes.deal(address(this), wethQuantity);
        ///@notice Wrap the weth to send from the sandboxRouter to the executor in a call.
        (bool depositSuccess, ) = address(WETH).call{value: wethQuantity}(
            abi.encodeWithSignature("deposit()")
        );
        require(depositSuccess, "Fudge");
        IERC20(WETH).approve(address(limitOrderExecutor), wethQuantity);
    }

    ///@notice Helper function to calculate the amountRequired from a swap.
    function _calculateExactAmountRequired(
        uint256 amountFilled,
        uint256 amountInRemaining,
        uint256 amountOutRemaining
    ) internal pure returns (uint256 amountOutRequired) {
        amountOutRequired = ConveyorMath.mul64U(
            ConveyorMath.divUU(amountOutRemaining, amountInRemaining),
            amountFilled
        );
    }

    function initialize10DimensionalOrderIdBundles()
        internal
        pure
        returns (bytes32[][] memory)
    {
        bytes32[][] memory orderIdBundles = new bytes32[][](10);

        for (uint256 i = 0; i < orderIdBundles.length; ++i) {
            orderIdBundles[i] = new bytes32[](1);
        }
        return orderIdBundles;
    }

    function dealSandboxRouterExecutionFee() internal {
        ///@notice Deal some ETH to compensate the fee
        cheatCodes.deal(address(sandboxRouter), type(uint128).max);
        cheatCodes.prank(address(sandboxRouter));
        ///@notice Wrap the weth to send from the sandboxRouter to the executor in a call.
        (bool depositSuccess, ) = address(WETH).call{value: 500000 ether}(
            abi.encodeWithSignature("deposit()")
        );
        require(depositSuccess, "Fudge");
    }

    function createSandboxCallMultiOrderMulticall()
        internal
        returns (
            SandboxLimitOrderRouter.SandboxMulticall memory,
            SandboxLimitOrderBook.SandboxLimitOrder[] memory,
            bytes32[] memory
        )
    {
        bytes32[] memory orderIds = placeNewMockMultiOrderMultiCall();

        uint256 cumulativeFee;

        SandboxLimitOrderBook.SandboxLimitOrder[]
            memory orders = new SandboxLimitOrderBook.SandboxLimitOrder[](10);
        {
            for (uint256 i = 0; i < orderIds.length; ++i) {
                SandboxLimitOrderBook.SandboxLimitOrder memory order = orderBook
                    .getSandboxLimitOrderById(orderIds[i]);
                cumulativeFee += order.feeRemaining;
                orders[i] = order;
            }
        }

        uint128[] memory fillAmounts = new uint128[](10);
        {
            ///@dev DAI/WETH Order 1 Full Fill Against WETH/DAI Order1
            fillAmounts[0] = 120000000000000000000000;
            ///@dev DAI/WETH Order 2 Full Fill Against WETH/DAI Order2
            fillAmounts[1] = 120000000000000000000000;
            ///@dev DAI/WETH Order 3 Partial Fill amount = order.amountInRemaining/2.
            fillAmounts[2] = 5000000000000000000;
            ///@dev DAI/WETH Order 4 Full Fill amount.
            fillAmounts[3] = 100000000000000000000;
            ///@dev DAI/WETH Order 4 Partial Fill amount = order.amountInRemaining/2.
            fillAmounts[4] = 5000000000000000000;
            ///@dev USDC/WETH Order 1 Partial Fill amount = order.amountInRemaining/5.
            fillAmounts[5] = 2000000000;
            ///@dev USDC/WETH Order 2 Full Fill.
            fillAmounts[6] = 10000000000;
            ///@dev USDC/WETH Order 3 Full Fill.
            fillAmounts[7] = 10000000000;
            ///@dev WETH/DAI Order 1 Full Fill Against DAI/WETH Order1
            fillAmounts[8] = 100000000000000000000;
            ///@dev WETH/DAI Order 2 Full Fill Against DAI/WETH Order2
            fillAmounts[9] = 100000000000000000000;
        }

        SandboxLimitOrderRouter.Call[]
            memory calls = new SandboxLimitOrderRouter.Call[](13);
        bytes32[][]
            memory orderIdBundles = initialize10DimensionalOrderIdBundles();
        {
            orderIdBundles[0][0] = orderIds[0];
            orderIdBundles[1][0] = orderIds[1];
            orderIdBundles[2][0] = orderIds[2];
            orderIdBundles[3][0] = orderIds[3];
            orderIdBundles[4][0] = orderIds[4];
            orderIdBundles[5][0] = orderIds[5];
            orderIdBundles[6][0] = orderIds[6];
            orderIdBundles[7][0] = orderIds[7];
            orderIdBundles[8][0] = orderIds[8];
            orderIdBundles[9][0] = orderIds[9];
            ///NOTE: Token0 = USDC & Token1 = WETH
            address usdcWethV2 = 0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc;
            //NOTE: Token0 = DAI & Token1 = WETH
            address daiWethV3 = 0xC2e9F25Be6257c210d7Adf0D4Cd6E3E881ba25f8;
            calls[0] = newUniV3Call(
                daiWethV3,
                address(sandboxRouter),
                address(sandboxRouter),
                true,
                110000000000000000000,
                DAI
            );
            calls[1] = newUniV2Call(
                usdcWethV2,
                0,
                30000000000000000, //Sum of the amountOutRemaining on all the usdc/weth orders. Should always be satisfiable even with the partial fill on order 1
                address(sandboxRouter)
            );
            calls[2] = amountOutRequiredCompensationCall(
                _calculateExactAmountRequired(
                    fillAmounts[0],
                    orders[0].amountInRemaining,
                    orders[0].amountOutRemaining
                ),
                address(mockOwner1),
                WETH
            );
            calls[3] = amountOutRequiredCompensationCall(
                _calculateExactAmountRequired(
                    fillAmounts[1],
                    orders[1].amountInRemaining,
                    orders[1].amountOutRemaining
                ),
                address(mockOwner2),
                WETH
            );
            calls[4] = amountOutRequiredCompensationCall(
                _calculateExactAmountRequired(
                    fillAmounts[2],
                    orders[2].amountInRemaining,
                    orders[2].amountOutRemaining
                ),
                address(mockOwner3),
                WETH
            );
            calls[5] = amountOutRequiredCompensationCall(
                _calculateExactAmountRequired(
                    fillAmounts[3],
                    orders[3].amountInRemaining,
                    orders[3].amountOutRemaining
                ),
                address(mockOwner4),
                WETH
            );
            calls[6] = amountOutRequiredCompensationCall(
                _calculateExactAmountRequired(
                    fillAmounts[4],
                    orders[4].amountInRemaining,
                    orders[4].amountOutRemaining
                ),
                address(mockOwner5),
                WETH
            );
            calls[7] = amountOutRequiredCompensationCall(
                _calculateExactAmountRequired(
                    fillAmounts[5],
                    orders[5].amountInRemaining,
                    orders[5].amountOutRemaining
                ),
                address(mockOwner6),
                WETH
            );
            calls[8] = amountOutRequiredCompensationCall(
                _calculateExactAmountRequired(
                    fillAmounts[6],
                    orders[6].amountInRemaining,
                    orders[6].amountOutRemaining
                ),
                address(mockOwner7),
                WETH
            );
            calls[9] = amountOutRequiredCompensationCall(
                _calculateExactAmountRequired(
                    fillAmounts[7],
                    orders[7].amountInRemaining,
                    orders[7].amountOutRemaining
                ),
                address(mockOwner8),
                WETH
            );

            calls[10] = amountOutRequiredCompensationCall(
                _calculateExactAmountRequired(
                    fillAmounts[8],
                    orders[8].amountInRemaining,
                    orders[8].amountOutRemaining
                ),
                address(mockOwner9),
                DAI
            );
            calls[11] = amountOutRequiredCompensationCall(
                _calculateExactAmountRequired(
                    fillAmounts[9],
                    orders[9].amountInRemaining,
                    orders[9].amountOutRemaining
                ),
                address(mockOwner10),
                DAI
            );

            calls[12] = feeCompensationCall(cumulativeFee);
            address[] memory transferAddresses = new address[](10);
            transferAddresses[0] = address(sandboxRouter); //Synthetically fill with WETH/DAI Order 10
            transferAddresses[1] = address(sandboxRouter); //Synthetically fill with WETH/DAI Order 9
            transferAddresses[2] = address(sandboxRouter);
            transferAddresses[3] = address(sandboxRouter);
            transferAddresses[4] = address(sandboxRouter);
            transferAddresses[5] = usdcWethV2;
            transferAddresses[6] = usdcWethV2;
            transferAddresses[7] = usdcWethV2;
            transferAddresses[8] = address(sandboxRouter); //Synthetically fill with DAI/WETH Order 1
            transferAddresses[9] = address(sandboxRouter); //Synthetically fill with DAI/WETH Order 2
            SandboxLimitOrderRouter.SandboxMulticall
                memory multiCall = newMockMulticall(
                    orderIdBundles,
                    fillAmounts,
                    transferAddresses,
                    calls
                );
            return (multiCall, orders, orderIds);
        }
    }

    ///@notice Helper function to create call to compensate the fees during execution
    function feeCompensationCall(uint256 cumulativeFee)
        public
        view
        returns (SandboxLimitOrderRouter.Call memory)
    {
        bytes memory callData = abi.encodeWithSignature(
            "transfer(address,uint256)",
            address(limitOrderExecutor),
            cumulativeFee
        );
        return SandboxLimitOrderRouter.Call({target: WETH, callData: callData});
    }

    ///@notice Helper function to create call to compensate the amountOutRequired during execution
    function amountOutRequiredCompensationCall(
        uint256 amountOutRequired,
        address receiver,
        address tokenOut
    ) public pure returns (SandboxLimitOrderRouter.Call memory) {
        bytes memory callData = abi.encodeWithSignature(
            "transfer(address,uint256)",
            address(receiver),
            amountOutRequired
        );
        return
            SandboxLimitOrderRouter.Call({
                target: tokenOut,
                callData: callData
            });
    }

    ///@notice Helper function to create a single mock call for a v2 swap.
    function newUniV2Call(
        address _lp,
        uint256 amount0Out,
        uint256 amount1Out,
        address _receiver
    ) public pure returns (SandboxLimitOrderRouter.Call memory) {
        bytes memory callData = abi.encodeWithSignature(
            "swap(uint256,uint256,address,bytes)",
            amount0Out,
            amount1Out,
            _receiver,
            new bytes(0)
        );
        return SandboxLimitOrderRouter.Call({target: _lp, callData: callData});
    }

    ///@notice Helper function to create a single mock call for a v3 swap.
    function newUniV3Call(
        address _lp,
        address _sender,
        address _receiver,
        bool _zeroForOne,
        uint256 _amountIn,
        address _tokenIn
    ) public pure returns (SandboxLimitOrderRouter.Call memory) {
        ///@notice Pack the required data for the call.
        bytes memory data = abi.encode(_zeroForOne, _tokenIn, _sender);
        ///@notice Encode the callData for the call.
        bytes memory callData = abi.encodeWithSignature(
            "swap(address,bool,int256,uint160,bytes)",
            _receiver,
            _zeroForOne,
            int256(_amountIn),
            _zeroForOne
                ? TickMath.MIN_SQRT_RATIO + 1
                : TickMath.MAX_SQRT_RATIO - 1,
            data
        );
        ///@notice Return the call
        return SandboxLimitOrderRouter.Call({target: _lp, callData: callData});
    }

    ///@notice Helper function to create a Sandox Multicall
    function newMockMulticall(
        bytes32[][] memory orderIdBundles,
        uint128[] memory fillAmounts,
        address[] memory transferAddresses,
        SandboxLimitOrderRouter.Call[] memory _calls
    ) public pure returns (SandboxLimitOrderRouter.SandboxMulticall memory) {
        return
            SandboxLimitOrderRouter.SandboxMulticall({
                orderIdBundles: orderIdBundles,
                fillAmounts: fillAmounts,
                transferAddresses: transferAddresses,
                calls: _calls
            });
    }

    ///@notice Helper function to place a single sandbox limit order
    function placeMockOrderWrapper(
        SandboxLimitOrderBook.SandboxLimitOrder memory order
    ) internal returns (bytes32 orderId) {
        //create a new array of orders
        SandboxLimitOrderBook.SandboxLimitOrder[]
            memory orderGroup = new SandboxLimitOrderBook.SandboxLimitOrder[](
                1
            );
        cheatCodes.deal(address(this), type(uint64).max);
        order.executionCreditRemaining = type(uint64).max;
        //add the order to the arrOrder and add the arrOrder to the orderGroup
        orderGroup[0] = order;

        //place order
        bytes32[] memory orderIds = sandboxLimitOrderBookWrapper
            .placeSandboxLimitOrder{value: type(uint64).max}(orderGroup);

        orderId = orderIds[0];
    }

    function newSandboxLimitOrder(
        bool buy,
        uint128 amountInRemaining,
        uint128 amountOutRemaining,
        address tokenIn,
        address tokenOut
    )
        internal
        view
        returns (SandboxLimitOrderBook.SandboxLimitOrder memory order)
    {
        //Initialize mock order
        order = SandboxLimitOrderBook.SandboxLimitOrder({
            fillPercent: 0,
            lastRefreshTimestamp: 0,
            expirationTimestamp: type(uint32).max,
            feeRemaining: 0,
            executionCreditRemaining: 0,
            amountInRemaining: amountInRemaining,
            amountOutRemaining: amountOutRemaining,
            owner: address(this),
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            orderId: bytes32(0)
        });
    }

    function placeMockSandboxLimitOrder(
        SandboxLimitOrderBook.SandboxLimitOrder memory order
    ) internal returns (bytes32 orderId) {
        //create a new array of orders
        SandboxLimitOrderBook.SandboxLimitOrder[]
            memory orderGroup = new SandboxLimitOrderBook.SandboxLimitOrder[](
                1
            );
        //add the order to the arrOrder and add the arrOrder to the orderGroup
        orderGroup[0] = order;
        cheatCodes.deal(address(this), type(uint64).max);
        order.executionCreditRemaining = type(uint64).max;
        //place order
        bytes32[] memory orderIds = orderBook.placeSandboxLimitOrder{
            value: type(uint64).max
        }(orderGroup);

        orderId = orderIds[0];
    }

    function placeMultipleMockOrder(
        SandboxLimitOrderBook.SandboxLimitOrder[] memory orderGroup
    ) internal returns (bytes32[] memory orderIds) {
        cheatCodes.deal(address(this), type(uint32).max * orderGroup.length);
        for (uint256 i = 0; i < orderGroup.length; i++) {
            orderGroup[i].executionCreditRemaining = type(uint32).max;
        }
        //place order
        orderIds = orderBook.placeSandboxLimitOrder{
            value: type(uint32).max * orderGroup.length
        }(orderGroup);
    }

    function placeNewMockMultiOrderMultiCall()
        internal
        returns (bytes32[] memory)
    {
        cheatCodes.prank(mockOwner1);
        swapHelper.swapEthForTokenWithUniV2(1000 ether, DAI);
        cheatCodes.prank(mockOwner1);
        IERC20(DAI).approve(address(limitOrderExecutor), type(uint128).max);
        bytes32[] memory orderIds = new bytes32[](10);
        ///@notice Dai/Weth sell limit order
        ///@dev amountInRemaining 1000 DAI amountOutRemaining 1 Wei
        SandboxLimitOrderBook.SandboxLimitOrder
            memory order1 = newSandboxLimitOrder(
                false,
                120000000000000000000000,
                100000000000000000000,
                DAI,
                WETH
            );
        cheatCodes.prank(mockOwner2);
        swapHelper.swapEthForTokenWithUniV2(1000 ether, DAI);
        cheatCodes.prank(mockOwner2);
        IERC20(DAI).approve(address(limitOrderExecutor), type(uint128).max);
        ///@notice Dai/Weth sell limit order
        ///@dev amountInRemaining 1000 DAI amountOutRemaining 1 Wei
        SandboxLimitOrderBook.SandboxLimitOrder
            memory order2 = newSandboxLimitOrder(
                false,
                120000000000000000000000,
                100000000000000000000,
                DAI,
                WETH
            );
        cheatCodes.prank(mockOwner3);
        swapHelper.swapEthForTokenWithUniV2(1000 ether, DAI);
        cheatCodes.prank(mockOwner3);
        IERC20(DAI).approve(address(limitOrderExecutor), type(uint128).max);
        ///@notice Dai/Weth sell limit order
        ///@dev amountInRemaining 1000 DAI amountOutRemaining 1 Wei
        SandboxLimitOrderBook.SandboxLimitOrder
            memory order3 = newSandboxLimitOrder(
                false,
                100000000000000000000,
                10000000000000000,
                DAI,
                WETH
            );
        cheatCodes.prank(mockOwner4);
        swapHelper.swapEthForTokenWithUniV2(1000 ether, DAI);
        cheatCodes.prank(mockOwner4);
        IERC20(DAI).approve(address(limitOrderExecutor), type(uint128).max);
        ///@notice Dai/Weth sell limit order
        ///@dev amountInRemaining 1000 DAI amountOutRemaining 1 Wei
        SandboxLimitOrderBook.SandboxLimitOrder
            memory order4 = newSandboxLimitOrder(
                false,
                100000000000000000000,
                10000000000000000,
                DAI,
                WETH
            );
        cheatCodes.prank(mockOwner5);
        swapHelper.swapEthForTokenWithUniV2(1000 ether, DAI);
        cheatCodes.prank(mockOwner5);
        IERC20(DAI).approve(address(limitOrderExecutor), type(uint128).max);
        ///@notice Dai/Weth sell limit order
        ///@dev amountInRemaining 1000 DAI amountOutRemaining 1 Wei
        SandboxLimitOrderBook.SandboxLimitOrder
            memory order5 = newSandboxLimitOrder(
                false,
                100000000000000000000,
                10000000000000000,
                DAI,
                WETH
            );

        cheatCodes.prank(mockOwner6);
        swapHelper.swapEthForTokenWithUniV2(1000 ether, USDC);
        cheatCodes.prank(mockOwner6);
        IERC20(USDC).approve(address(limitOrderExecutor), type(uint128).max);
        ///@notice USDC/Weth sell limit order
        ///@dev amountInRemaining 10000 USDC amountOutRemaining 1 Wei
        SandboxLimitOrderBook.SandboxLimitOrder
            memory order6 = newSandboxLimitOrder(
                false,
                10000000000,
                10000000000000000,
                USDC,
                WETH
            );
        cheatCodes.prank(mockOwner7);
        swapHelper.swapEthForTokenWithUniV2(1000 ether, USDC);
        cheatCodes.prank(mockOwner7);
        IERC20(USDC).approve(address(limitOrderExecutor), type(uint128).max);
        ///@notice USDC/Weth sell limit order
        ///@dev amountInRemaining 10000 USDC amountOutRemaining 1 Wei
        SandboxLimitOrderBook.SandboxLimitOrder
            memory order7 = newSandboxLimitOrder(
                false,
                10000000000,
                10000000000000000,
                USDC,
                WETH
            );

        cheatCodes.prank(mockOwner8);
        swapHelper.swapEthForTokenWithUniV2(1000 ether, USDC);
        cheatCodes.prank(mockOwner8);
        IERC20(USDC).approve(address(limitOrderExecutor), type(uint128).max);

        ///@notice USDC/Weth sell limit order
        ///@dev amountInRemaining 10000 USDC amountOutRemaining 1 Wei
        SandboxLimitOrderBook.SandboxLimitOrder
            memory order8 = newSandboxLimitOrder(
                false,
                10000000000,
                10000000000000000,
                USDC,
                WETH
            );
        cheatCodes.deal(address(mockOwner9), 1000000 ether);
        cheatCodes.prank(mockOwner9);
        IERC20(WETH).approve(address(limitOrderExecutor), type(uint128).max);

        {
            cheatCodes.prank(mockOwner9);
            ///@notice Wrap the weth to send to the executor in a call.
            (bool success, ) = address(WETH).call{value: 1000000 ether}(
                abi.encodeWithSignature("deposit()")
            );
            require(success, "fudge");
        }
        ///@notice Weth/Dai sell limit order
        ///@dev amountInRemaining 1000 WETH amountOutRemaining 120000.0 DAI
        SandboxLimitOrderBook.SandboxLimitOrder
            memory order9 = newSandboxLimitOrder(
                true,
                100000000000000000000,
                120000000000000000000000,
                WETH,
                DAI
            );
        cheatCodes.deal(address(mockOwner10), 1000000 ether);
        cheatCodes.prank(mockOwner10);
        IERC20(WETH).approve(address(limitOrderExecutor), type(uint128).max);

        {
            cheatCodes.prank(mockOwner10);
            ///@notice Wrap the weth to send to the executor in a call.
            (bool depositSuccess, ) = address(WETH).call{value: 1000000 ether}(
                abi.encodeWithSignature("deposit()")
            );
            require(depositSuccess, "fudge");
        }
        ///@notice Weth/Dai sell limit order
        ///@dev amountInRemaining 1000 WETH amountOutRemaining 120000.0 DAI
        SandboxLimitOrderBook.SandboxLimitOrder
            memory order10 = newSandboxLimitOrder(
                true,
                100000000000000000000,
                120000000000000000000000,
                WETH,
                DAI
            );
        {
            orderIds[0] = placeMockOrderCustomOwner(order1, mockOwner1);
            orderIds[1] = placeMockOrderCustomOwner(order2, mockOwner2);
            orderIds[2] = placeMockOrderCustomOwner(order3, mockOwner3);
            orderIds[3] = placeMockOrderCustomOwner(order4, mockOwner4);
            orderIds[4] = placeMockOrderCustomOwner(order5, mockOwner5);
            orderIds[5] = placeMockOrderCustomOwner(order6, mockOwner6);
            orderIds[6] = placeMockOrderCustomOwner(order7, mockOwner7);
            orderIds[7] = placeMockOrderCustomOwner(order8, mockOwner8);
            orderIds[8] = placeMockOrderCustomOwner(order9, mockOwner9);
            orderIds[9] = placeMockOrderCustomOwner(order10, mockOwner10);
        }
        return orderIds;
    }

    function placeMockOrderCustomOwner(
        SandboxLimitOrderBook.SandboxLimitOrder memory order,
        address owner
    ) internal returns (bytes32 orderId) {
        //create a new array of orders
        SandboxLimitOrderBook.SandboxLimitOrder[]
            memory orderGroup = new SandboxLimitOrderBook.SandboxLimitOrder[](
                1
            );
        //add the order to the arrOrder and add the arrOrder to the orderGroup
        orderGroup[0] = order;
        cheatCodes.deal(address(owner), type(uint64).max);

        order.executionCreditRemaining = type(uint64).max;
        cheatCodes.prank(owner);
        //place order
        bytes32[] memory orderIds = orderBook.placeSandboxLimitOrder{
            value: type(uint64).max
        }(orderGroup);

        orderId = orderIds[0];
    }

    function placeMockOrder(
        SandboxLimitOrderBook.SandboxLimitOrder memory order
    ) internal returns (bytes32 orderId) {
        //create a new array of orders
        SandboxLimitOrderBook.SandboxLimitOrder[]
            memory orderGroup = new SandboxLimitOrderBook.SandboxLimitOrder[](
                1
            );
        //add the order to the arrOrder and add the arrOrder to the orderGroup
        orderGroup[0] = order;
        cheatCodes.deal(address(this), type(uint64).max);

        order.executionCreditRemaining = type(uint64).max;

        //place order
        bytes32[] memory orderIds = orderBook.placeSandboxLimitOrder{
            value: type(uint64).max
        }(orderGroup);

        orderId = orderIds[0];
    }
}

//wrapper around LimitOrderSwapRouter to expose internal functions for testing
contract LimitOrderExecutorWrapper is ConveyorExecutor {
    constructor(
        address _weth,
        address _usdc,
        address _limitOrderQuoter,
        bytes32[] memory _initBytecodes,
        address[] memory _dexFactories,
        bool[] memory _isUniV2,
        uint256 _executionCredit
    )
        ConveyorExecutor(
            _weth,
            _usdc,
            _limitOrderQuoter,
            _initBytecodes,
            _dexFactories,
            _isUniV2,
            _executionCredit
        )
    {}

    function requireConveyorFeeIsPaid(
        uint256 contractBalancePreExecution,
        uint256 expectedAccumulatedFees
    ) public view {
        _requireConveyorFeeIsPaid(
            contractBalancePreExecution,
            expectedAccumulatedFees
        );
    }
}

contract SandboxLimitOrderBookWrapper is SandboxLimitOrderBook {
    constructor(
        address _limitOrderExecutor,
        address _weth,
        address _usdc,
        uint256 _minExecutionCredit
    )
        SandboxLimitOrderBook(
            _limitOrderExecutor,
            _weth,
            _usdc,
            _minExecutionCredit
        )
    {}

    function _getSandboxLimitOrderById(bytes32 orderId)
        public
        view
        returns (SandboxLimitOrder memory)
    {
        return getSandboxLimitOrderById(orderId);
    }

    function initializePreSandboxExecutionState(
        bytes32[][] calldata orderIdBundles,
        uint128[] calldata fillAmounts
    )
        public
        view
        returns (PreSandboxExecutionState memory preSandboxExecutionState)
    {
        return _initializePreSandboxExecutionState(orderIdBundles, fillAmounts);
    }

    function validateSandboxExecutionAndFillOrders(
        bytes32[][] calldata orderIdBundles,
        uint128[] calldata fillAmounts,
        PreSandboxExecutionState memory preSandboxExecutionState
    ) public {
        _validateSandboxExecutionAndFillOrders(
            orderIdBundles,
            fillAmounts,
            preSandboxExecutionState
        );
    }

    function executeSandboxLimitOrders(
        SandboxLimitOrderBook.SandboxLimitOrder[] memory orders,
        SandboxLimitOrderRouter.SandboxMulticall calldata sandboxMulticall,
        address limitOrderExecutor
    ) public {
        IConveyorExecutor(address(limitOrderExecutor))
            .executeSandboxLimitOrders(orders, sandboxMulticall);
    }
}
