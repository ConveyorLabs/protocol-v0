// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "./utils/test.sol";
import "./utils/Console.sol";
import "./utils/Utils.sol";
import "../LimitOrderBook.sol";
import "../interfaces/ILimitOrderBook.sol";
import "../../lib/interfaces/uniswap-v2/IUniswapV2Router02.sol";
import "../../lib/interfaces/uniswap-v2/IUniswapV2Factory.sol";
import "../../lib/interfaces/token/IERC20.sol";
import "./utils/Swap.sol";
import "../LimitOrderQuoter.sol";
import "../ConveyorExecutor.sol";
import "../LimitOrderSwapRouter.sol";

interface CheatCodes {
    function prank(address) external;

    function deal(address who, uint256 amount) external;

    function expectEmit(
        bool,
        bool,
        bool,
        bool
    ) external;

    function expectRevert(bytes memory) external;
}

interface Errors {
    error WithdrawAmountExceedsExecutionCredit(
        uint256 withdrawAmount,
        uint256 executionCredit
    );

    error InsufficientExecutionCredit(
        uint256 executionCredit,
        uint256 minExecutionCredit
    );
    error InsufficientMsgValue();
    error OrderDoesNotExist(bytes32 orderId);
}

contract LimitOrderBookTest is DSTest {
    CheatCodes cheatCodes;
    ConveyorExecutor limitOrderExecutor;
    LimitOrderQuoter limitOrderQuoter;
    Swap swapHelper;

    ILimitOrderBook orderBook;

    event OrderPlaced(bytes32[] orderIds);
    event OrderCanceled(bytes32[] orderIds);
    event OrderUpdated(bytes32[] orderIds);

    //----------------State variables for testing--------------------
    ///@notice initialize swap helper
    address uniV2Addr = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    address swapToken = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
    address swapToken1 = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984;

    uint256 immutable MAX_UINT = type(uint256).max;
    //Factory and router address's
    address _sushiSwapRouterAddress =
        0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;
    address _uniV2FactoryAddress = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address _uniV3FactoryAddress = 0x1F98431c8aD98523631AE4a59f267346ea31F984;

    //Chainlink ERC20 address

    bytes32 _uniswapV2HexDem =
        0x96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f;

    address aggregatorV3Address = 0x169E633A2D1E6c10dD91238Ba11c4A708dfEF37C;

    address swapRouter = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    //Initialize array of Dex specifications
    bytes32[] _hexDems = [_uniswapV2HexDem, _uniswapV2HexDem];
    address[] _dexFactories = [_uniV2FactoryAddress, _uniV3FactoryAddress];
    bool[] _isUniV2 = [true, false];
    uint256 alphaXDivergenceThreshold = 3402823669209385000000000000000000000;
    uint256 minExecutionCredit = 100000000;

    function setUp() public {
        cheatCodes = CheatCodes(HEVM_ADDRESS);

        swapHelper = new Swap(_sushiSwapRouterAddress, WETH);
        cheatCodes.deal(address(swapHelper), MAX_UINT);

        limitOrderQuoter = new LimitOrderQuoter(
            0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
        );

        limitOrderExecutor = new ConveyorExecutor(
            0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
            0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48,
            address(limitOrderQuoter),
            _hexDems,
            _dexFactories,
            _isUniV2,
            minExecutionCredit
        );

        //Wrapper contract to test internal functions
        orderBook = ILimitOrderBook(limitOrderExecutor.LIMIT_ORDER_ROUTER());
    }

    ///@notice Test get order by id
    function testGetLimitOrderById() public {
        IERC20(swapToken).approve(address(limitOrderExecutor), MAX_UINT);

        swapHelper.swapEthForTokenWithUniV2(20 ether, swapToken);

        //create a new order
        LimitOrderBook.LimitOrder memory order = newOrder(
            swapToken,
            WETH,
            245000000000000000000,
            5,
            5
        );
        //place a mock order
        bytes32 orderId = placeMockOrder(order);

        LimitOrderBook.LimitOrder memory returnedOrder = orderBook
            .getLimitOrderById(orderId);
        (orderId);

        // assert that the two orders are the same
        assertEq(returnedOrder.tokenIn, order.tokenIn);
        assertEq(returnedOrder.tokenOut, order.tokenOut);
        assertEq(returnedOrder.orderId, orderId);
        assertEq(returnedOrder.price, order.price);
        assertEq(returnedOrder.quantity, order.quantity);
    }

    ///@notice Test fail get order by id order does not exist
    function testFailGetLimitOrderById_OrderDoesNotExist() public view {
        orderBook.getLimitOrderById(bytes32(0));
    }

    ///@notice Test palce order fuzz test
    function testPlaceOrder(uint256 swapAmount, uint256 executionPrice) public {
        cheatCodes.deal(address(this), MAX_UINT);
        IERC20(swapToken).approve(address(limitOrderExecutor), MAX_UINT);

        //if the fuzzed amount is enough to complete the swap
        try swapHelper.swapEthForTokenWithUniV2(swapAmount, swapToken) returns (
            uint256 amountOut
        ) {
            LimitOrderBook.LimitOrder memory order = newOrder(
                swapToken,
                WETH,
                uint128(executionPrice),
                uint112(amountOut),
                uint112(amountOut)
            );

            bytes32 orderId = placeMockOrder(order);

            //check that the orderId is not zero value
            assert((orderId != bytes32(0)));
            LimitOrderBook.OrderType orderType = orderBook.addressToOrderIds(
                address(this),
                orderId
            );
            assert(orderType == LimitOrderBook.OrderType.PendingLimitOrder);
            assertEq(
                orderBook.totalOrdersQuantity(
                    keccak256(abi.encode(address(this), swapToken))
                ),
                amountOut
            );

            assertEq(orderBook.totalOrdersPerAddress(address(this)), 1);
        } catch {}
    }

    ///@notice Test palce order fuzz test
    function testIncreaseExecutionCredit(
        uint256 swapAmount,
        uint256 executionPrice,
        uint64 executionCreditAmount
    ) public {
        IERC20(swapToken).approve(address(limitOrderExecutor), MAX_UINT);

        //if the fuzzed amount is enough to complete the swap
        try swapHelper.swapEthForTokenWithUniV2(swapAmount, swapToken) returns (
            uint256 amountOut
        ) {
            LimitOrderBook.LimitOrder memory order = newOrder(
                swapToken,
                WETH,
                uint128(executionPrice),
                uint112(amountOut),
                uint112(amountOut)
            );

            bytes32 orderId = placeMockOrder(order);
            if (executionCreditAmount == 0) {
                cheatCodes.expectRevert(
                    abi.encodeWithSelector(Errors.InsufficientMsgValue.selector)
                );
                (bool reverted, ) = address(orderBook).call(
                    abi.encodeWithSignature(
                        "increaseExecutionCredit(bytes32)",
                        orderId
                    )
                );
                assertTrue(reverted);
            } else {
                cheatCodes.deal(
                    address(this),
                    executionCreditAmount > address(this).balance
                        ? executionCreditAmount - address(this).balance
                        : 0
                );
                orderBook.increaseExecutionCredit{value: executionCreditAmount}(
                    orderId
                );
                //check that the orderId is not zero value
                assert((orderId != bytes32(0)));
                LimitOrderBook.OrderType orderType = orderBook
                    .addressToOrderIds(address(this), orderId);
                LimitOrderBook.LimitOrder memory returnedOrder = orderBook
                    .getLimitOrderById(orderId);
                assert(
                    returnedOrder.executionCredit ==
                        uint128(executionCreditAmount) + type(uint64).max
                );
                assert(orderType == LimitOrderBook.OrderType.PendingLimitOrder);
                assertEq(
                    orderBook.totalOrdersQuantity(
                        keccak256(abi.encode(address(this), swapToken))
                    ),
                    amountOut
                );

                assertEq(orderBook.totalOrdersPerAddress(address(this)), 1);
            }
        } catch {
            if (!(executionCreditAmount == 0)) {
                cheatCodes.deal(
                    address(this),
                    type(uint256).max > address(this).balance
                        ? type(uint256).max - address(this).balance
                        : 0
                );
                cheatCodes.expectRevert(
                    abi.encodeWithSelector(
                        Errors.OrderDoesNotExist.selector,
                        bytes32(0)
                    )
                );

                (bool reverted, ) = address(orderBook).call{
                    value: executionCreditAmount
                }(
                    abi.encodeWithSignature(
                        "increaseExecutionCredit(bytes32)",
                        bytes32(0)
                    )
                );
                assertTrue(reverted);
            }
        }
    }

    ///@notice Test palce order fuzz test
    function testDecreaseExecutionCredit(
        uint128 swapAmount,
        uint128 executionPrice,
        uint128 executionCreditAmount
    ) public {
        IERC20(swapToken).approve(address(limitOrderExecutor), MAX_UINT);

        //if the fuzzed amount is enough to complete the swap
        try swapHelper.swapEthForTokenWithUniV2(swapAmount, swapToken) returns (
            uint256 amountOut
        ) {
            LimitOrderBook.LimitOrder memory order = newOrder(
                swapToken,
                WETH,
                uint128(executionPrice),
                uint112(amountOut),
                uint112(amountOut)
            );

            bytes32 orderId = placeMockOrder(order);
            uint128 executionCreditStateBefore = orderBook
                .getLimitOrderById(orderId)
                .executionCredit;
            if (executionCreditAmount > executionCreditStateBefore) {
                cheatCodes.expectRevert(
                    abi.encodeWithSelector(
                        Errors.WithdrawAmountExceedsExecutionCredit.selector,
                        executionCreditAmount,
                        executionCreditStateBefore
                    )
                );
                (bool reverted1, ) = address(orderBook).call(
                    abi.encodeWithSignature(
                        "decreaseExecutionCredit(bytes32,uint128)",
                        orderId,
                        executionCreditAmount
                    )
                );
                assertTrue(reverted1);
            } else {
                if (
                    executionCreditStateBefore - executionCreditAmount <
                    minExecutionCredit
                ) {
                    cheatCodes.expectRevert(
                        abi.encodeWithSelector(
                            Errors.InsufficientExecutionCredit.selector,
                            uint256(
                                executionCreditStateBefore -
                                    executionCreditAmount
                            ),
                            uint256(minExecutionCredit)
                        )
                    );
                    (bool reverted2, ) = address(orderBook).call(
                        abi.encodeWithSignature(
                            "decreaseExecutionCredit(bytes32,uint128)",
                            orderId,
                            executionCreditAmount
                        )
                    );
                    assertTrue(reverted2);
                } else {
                    orderBook.decreaseExecutionCredit(
                        orderId,
                        executionCreditAmount
                    );
                    //check that the orderId is not zero value
                    assert((orderId != bytes32(0)));
                    LimitOrderBook.OrderType orderType = orderBook
                        .addressToOrderIds(address(this), orderId);
                    LimitOrderBook.LimitOrder memory returnedOrder = orderBook
                        .getLimitOrderById(orderId);
                    assert(
                        returnedOrder.executionCredit ==
                            uint128(executionCreditStateBefore) -
                                uint128(executionCreditAmount)
                    );
                    assert(
                        orderType == LimitOrderBook.OrderType.PendingLimitOrder
                    );
                    assertEq(
                        orderBook.totalOrdersQuantity(
                            keccak256(abi.encode(address(this), swapToken))
                        ),
                        amountOut
                    );

                    assertEq(orderBook.totalOrdersPerAddress(address(this)), 1);
                }
            }
        } catch {
            cheatCodes.expectRevert(
                abi.encodeWithSelector(
                    Errors.OrderDoesNotExist.selector,
                    bytes32(0)
                )
            );

            (bool reverted, ) = address(orderBook).call(
                abi.encodeWithSignature(
                    "decreaseExecutionCredit(bytes32,uint128)",
                    bytes32(0),
                    executionCreditAmount
                )
            );
            assertTrue(reverted);
        }
    }

    function testGetOrderIds() public {
        cheatCodes.deal(address(this), MAX_UINT);
        IERC20(swapToken).approve(address(limitOrderExecutor), MAX_UINT);
        //if the fuzzed amount is enough to complete the swap
        swapHelper.swapEthForTokenWithUniV2(10000, swapToken);

        ///@notice Place orders
        bytes32 orderId1 = placeMockOrder(
            newOrder(swapToken, WETH, uint128(1), uint112(1), uint112(1))
        );

        bytes32 orderId2 = placeMockOrder(
            newOrder(swapToken, WETH, uint128(1), uint112(1), uint112(1))
        );

        orderBook.cancelOrder(orderId2);

        uint256 orderIdsLength = orderBook.getAllOrderIdsLength(address(this));

        bytes32[] memory pendingLimitOrders = orderBook.getOrderIds(
            address(this),
            LimitOrderBook.OrderType.PendingLimitOrder,
            0,
            orderIdsLength
        );

        bytes32[] memory canceledLimitOrders = orderBook.getOrderIds(
            address(this),
            LimitOrderBook.OrderType.CanceledLimitOrder,
            0,
            orderIdsLength
        );

        assertEq(pendingLimitOrders.length, 1);
        assertEq(canceledLimitOrders.length, 1);

        assertEq(pendingLimitOrders[0], orderId1);
        assertEq(canceledLimitOrders[0], orderId2);
    }

    ///@notice Test fail place order InsufficientAlllowanceForOrderPlacement
    function testFailPlaceOrder_InsufficientAllowanceForOrderPlacement(
        uint256 swapAmount,
        uint256 executionPrice
    ) public {
        cheatCodes.deal(address(this), MAX_UINT);

        //if the fuzzed amount is enough to complete the swap
        try swapHelper.swapEthForTokenWithUniV2(swapAmount, swapToken) returns (
            uint256 amountOut
        ) {
            LimitOrderBook.LimitOrder memory order = newOrder(
                swapToken,
                WETH,
                uint128(executionPrice),
                uint128(amountOut),
                uint128(amountOut)
            );

            bytes32 orderId = placeMockOrder(order);

            //check that the orderId is not zero value
            assert((orderId != bytes32(0)));

            assertEq(
                orderBook.totalOrdersQuantity(
                    keccak256(abi.encode(address(this), swapToken))
                ),
                amountOut
            );

            assertEq(orderBook.totalOrdersPerAddress(address(this)), 1);
        } catch {
            require(false, "swap failed");
        }
    }

    ///@notice Test fail place order InsufficientWalletBalance
    function testFailPlaceOrder_InsufficientWalletBalance() public {
        IERC20(swapToken).approve(address(limitOrderExecutor), MAX_UINT);

        LimitOrderBook.LimitOrder memory order = newOrder(
            swapToken,
            WETH,
            245000000000000000000,
            5,
            5
        );

        placeMockOrder(order);
    }

    ///@notice Test fail place order InsufficientWalletBalance
    function testFailPlaceOrder_InsufficientExecutionCredit() public {
        IERC20(swapToken).approve(address(limitOrderExecutor), MAX_UINT);

        LimitOrderBook.LimitOrder memory order = newOrder(
            swapToken,
            WETH,
            245000000000000000000,
            5,
            5
        );

        //create a new array of orders
        LimitOrderBook.LimitOrder[]
            memory orderGroup = new LimitOrderBook.LimitOrder[](1);
        //add the order to the arrOrder and add the arrOrder to the orderGroup
        orderGroup[0] = order;

        //place order
        orderBook.placeLimitOrder(orderGroup);
    }

    ///@notice Test Fail Place order IncongruentTokenInOrderGroup
    function testFailPlaceOrder_IncongruentTokenInOrderGroup(
        uint256 swapAmount,
        uint256 executionPrice,
        uint256 swapAmount1,
        uint256 executionPrice1
    ) public {
        cheatCodes.deal(address(this), MAX_UINT);
        IERC20(swapToken).approve(address(limitOrderExecutor), MAX_UINT);

        //swap 20 ether for the swap token
        //if the fuzzed amount is enough to complete the swap
        try swapHelper.swapEthForTokenWithUniV2(swapAmount, swapToken) returns (
            uint256 amountOut
        ) {
            LimitOrderBook.LimitOrder memory order1 = newOrder(
                swapToken,
                WETH,
                uint128(executionPrice),
                uint128(amountOut),
                uint128(amountOut)
            );

            try
                swapHelper.swapEthForTokenWithUniV2(swapAmount1, swapToken1)
            returns (uint256 amountOut1) {
                LimitOrderBook.LimitOrder memory order2 = newOrder(
                    swapToken1,
                    WETH,
                    uint128(executionPrice1),
                    uint112(amountOut1),
                    uint112(amountOut1)
                );

                //create a new array of orders
                LimitOrderBook.LimitOrder[]
                    memory orderGroup = new LimitOrderBook.LimitOrder[](2);
                //add the order to the arrOrder and add the arrOrder to the orderGroup
                orderGroup[0] = order1;
                orderGroup[1] = order2;

                //place order
                placeMultipleMockOrder(orderGroup);
            } catch {
                require(false, "swap 1 failed");
            }
        } catch {
            require(false, "swap 0 failed");
        }
    }

    ///@notice Test update order
    function testUpdateOrder(
        uint128 price,
        uint64 quantity,
        uint128 amountOutMin,
        uint128 newPrice,
        uint64 newQuantity
    ) public {
        if (
            !(price == 0 ||
                quantity == 0 ||
                amountOutMin == 0 ||
                newPrice == 0 ||
                newQuantity == 0)
        ) {
            cheatCodes.deal(address(this), MAX_UINT);
            IERC20(swapToken).approve(address(limitOrderExecutor), MAX_UINT);

            cheatCodes.deal(address(swapHelper), MAX_UINT);
            swapHelper.swapEthForTokenWithUniV2(100000000000 ether, swapToken);

            //create a new order
            LimitOrderBook.LimitOrder memory order = newOrder(
                swapToken,
                WETH,
                price,
                quantity,
                amountOutMin
            );

            //place a mock order
            bytes32 orderId = placeMockOrder(order);

            //submit the updated order
            orderBook.updateOrder(orderId, newPrice, newQuantity);

            LimitOrderBook.LimitOrder memory updatedOrder = orderBook
                .getLimitOrderById(orderId);

            //Cache the total orders value after the update
            uint256 totalOrdersValueAfter = orderBook.getTotalOrdersValue(
                swapToken
            );

            //Make sure the order was updated properly
            assertEq(newQuantity, totalOrdersValueAfter);
            assertEq(newQuantity, updatedOrder.quantity);
            assertEq(newPrice, updatedOrder.price);
        }
    }

    ///@notice Test fail update order on invalid sender
    function testFailUpdateOrder_MsgSenderIsNotOrderOwner(
        uint128 price,
        uint64 quantity,
        uint128 amountOutMin,
        uint128 newPrice,
        uint64 newQuantity
    ) public {
        cheatCodes.deal(address(this), MAX_UINT);
        IERC20(swapToken).approve(address(limitOrderExecutor), MAX_UINT);

        cheatCodes.deal(address(swapHelper), MAX_UINT);
        swapHelper.swapEthForTokenWithUniV2(100000000000 ether, swapToken);

        //create a new order
        LimitOrderBook.LimitOrder memory order = newOrder(
            swapToken,
            WETH,
            price,
            quantity,
            amountOutMin
        );

        //submit the updated order

        bytes32 orderId = placeMockOrder(order);
        cheatCodes.prank(tx.origin);
        orderBook.updateOrder(orderId, newPrice, newQuantity);
    }

    ///@notice Test fail update order insufficient allowance
    function testFailUpdateOrder_InsufficientAllowanceForOrderUpdate(
        uint128 price,
        uint64 quantity,
        uint128 amountOutMin,
        uint128 newPrice
    ) public {
        cheatCodes.deal(address(this), MAX_UINT);
        IERC20(swapToken).approve(address(limitOrderExecutor), quantity);

        cheatCodes.deal(address(swapHelper), MAX_UINT);
        swapHelper.swapEthForTokenWithUniV2(100000000000 ether, swapToken);

        //create a new order
        LimitOrderBook.LimitOrder memory order = newOrder(
            swapToken,
            WETH,
            price,
            quantity,
            amountOutMin
        );

        //place a mock order
        bytes32 orderId = placeMockOrder(order);

        //submit the updated order should revert since approved quantity is less than order quantity
        orderBook.updateOrder(orderId, newPrice, quantity + 1);
    }

    ///@notice Test fail update order order does not exist
    function testFailUpdateOrder_OrderDoesNotExist(
        uint256 swapAmount,
        uint256 executionPrice,
        bytes32 orderId
    ) public {
        IERC20(swapToken).approve(address(limitOrderExecutor), MAX_UINT);

        try swapHelper.swapEthForTokenWithUniV2(swapAmount, swapToken) returns (
            uint256 amountOut
        ) {
            //create a new order
            LimitOrderBook.LimitOrder memory order = newOrder(
                swapToken,
                WETH,
                uint128(amountOut),
                uint128(executionPrice),
                uint128(executionPrice)
            );

            //place a mock order
            placeMockOrder(order);

            orderBook.updateOrder(orderId, 100, 0);
        } catch {
            require(false, "swap failed");
        }
    }

    //Test cancel order
    function testCancelOrder() public {
        IERC20(swapToken).approve(address(limitOrderExecutor), MAX_UINT);

        uint256 amountOut = swapHelper.swapEthForTokenWithUniV2(
            100000,
            swapToken
        );
        //create a new order
        LimitOrderBook.LimitOrder memory order = newOrder(
            swapToken,
            WETH,
            uint128(amountOut),
            uint128(1),
            uint128(1)
        );
        //place a mock order
        bytes32 orderId = placeMockOrder(order);

        //submit the updated order
        orderBook.cancelOrder(orderId);
    }

    ///@notice Test Fail cancel order order does not exist
    function testFailCancelOrder_OrderDoesNotExist(bytes32 orderId) public {
        //submit the updated order
        orderBook.cancelOrder(orderId);
    }

    ///@notice Test to cancel multiple order
    function testCancelOrders() public {
        IERC20(swapToken).approve(address(limitOrderExecutor), MAX_UINT);

        uint256 amountOut = swapHelper.swapEthForTokenWithUniV2(
            100000,
            swapToken
        );
        //Create a new order
        LimitOrderBook.LimitOrder memory order1 = newOrder(
            swapToken,
            WETH,
            uint128(amountOut / 2),
            uint128(1),
            uint128(1)
        );
        //Create a second order
        LimitOrderBook.LimitOrder memory order2 = newOrder(
            swapToken,
            WETH,
            uint128((amountOut / 2) - 1),
            uint128(1),
            uint128(1)
        );

        //create a new array of orders
        LimitOrderBook.LimitOrder[]
            memory orderGroup = new LimitOrderBook.LimitOrder[](2);
        //add the order to the arrOrder and add the arrOrder to the orderGroup
        orderGroup[0] = order1;
        orderGroup[1] = order2;

        //place order
        bytes32[] memory orderIds = placeMultipleMockOrder(orderGroup);

        //Cancel the orders
        orderBook.cancelOrders(orderIds);
    }

    ///@notice Test Fail cancel orders OrderDoesNotExist
    function testFailCancelOrders_OrderDoesNotExist(
        bytes32 orderId,
        bytes32 orderId1
    ) public {
        IERC20(swapToken).approve(address(limitOrderExecutor), MAX_UINT);

        //place order
        bytes32[] memory orderIds = new bytes32[](2);
        orderIds[0] = orderId;
        orderIds[1] = orderId1;
        orderBook.cancelOrders(orderIds);
    }

    ///@notice Test get total orders value
    function testGetTotalOrdersValue() public {
        swapHelper.swapEthForTokenWithUniV2(20 ether, swapToken);
        IERC20(swapToken).approve(address(limitOrderExecutor), MAX_UINT);

        //create a new order
        LimitOrderBook.LimitOrder memory order = newOrder(
            swapToken,
            WETH,
            245000000000000000000,
            5,
            5
        );

        //place a mock order
        placeMockOrder(order);

        uint256 totalOrdersValue = orderBook.getTotalOrdersValue(swapToken);
        assertEq(5, totalOrdersValue);
    }

    //------------------Helper functions-----------------------

    function newOrder(
        address tokenIn,
        address tokenOut,
        uint128 price,
        uint128 quantity,
        uint128 amountOutMin
    ) internal view returns (LimitOrderBook.LimitOrder memory order) {
        //Initialize mock order
        order = LimitOrderBook.LimitOrder({
            stoploss: false,
            buy: false,
            taxed: false,
            lastRefreshTimestamp: 0,
            expirationTimestamp: uint32(MAX_UINT),
            feeIn: 0,
            feeOut: 0,
            taxIn: 0,
            executionCredit: 0,
            price: price,
            amountOutMin: amountOutMin,
            quantity: quantity,
            owner: address(this),
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            orderId: bytes32(0)
        });
    }

    function placeMockOrder(LimitOrderBook.LimitOrder memory order)
        internal
        returns (bytes32 orderId)
    {
        //create a new array of orders
        LimitOrderBook.LimitOrder[]
            memory orderGroup = new LimitOrderBook.LimitOrder[](1);
        //add the order to the arrOrder and add the arrOrder to the orderGroup
        orderGroup[0] = order;
        cheatCodes.deal(address(this), type(uint64).max);
        order.executionCredit = type(uint64).max;
        //place order
        bytes32[] memory orderIds = orderBook.placeLimitOrder{
            value: type(uint64).max
        }(orderGroup);

        orderId = orderIds[0];
    }

    receive() external payable {}

    function placeMultipleMockOrder(
        LimitOrderBook.LimitOrder[] memory orderGroup
    ) internal returns (bytes32[] memory orderIds) {
        cheatCodes.deal(address(this), type(uint32).max * orderGroup.length);
        for (uint256 i = 0; i < orderGroup.length; i++) {
            orderGroup[i].executionCredit = type(uint32).max;
        }
        //place order
        orderIds = orderBook.placeLimitOrder{
            value: type(uint32).max * orderGroup.length
        }(orderGroup);
    }
}
