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

interface CheatCodes {
    function prank(address) external;

    function deal(address who, uint256 amount) external;

    function expectEmit(
        bool,
        bool,
        bool,
        bool
    ) external;
}

contract LimitOrderExecutorTest is DSTest {
    ILimitOrderRouter limitOrderRouter;
    ILimitOrderBook orderBook;
    LimitOrderRouter limitOrderRouterWrapper;
    LimitOrderExecutorWrapper limitOrderExecutor;
    LimitOrderQuoter limitOrderQuoter;

    ScriptRunner scriptRunner;

    Swap swapHelper;
    Swap swapHelperUniV2;

    address uniV2Addr = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    //Initialize cheatcodes
    CheatCodes cheatCodes;

    //Test Token Address's
    address WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address LINK = 0x218532a12a389a4a92fC0C5Fb22901D1c19198aA;
    address UNI = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984;
    address USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address TAXED_TOKEN = 0xE7eaec9Bca79d537539C00C58Ae93117fB7280b9; //
    address TAXED_TOKEN_1 = 0xe0a189C975e4928222978A74517442239a0b86ff; //
    address TAXED_TOKEN_2 = 0xd99793A840cB0606456916d1CF5eA199ED93Bf97; //6% tax CHAOS token 27
    address TAXED_TOKEN_3 = 0xcFEB09C3c5F0f78aD72166D55f9e6E9A60e96eEC;

    //MAX_UINT for testing
    uint256 constant MAX_UINT = 2**256 - 1;

    uint32 constant MAX_U32 = 2**32 - 1;

    //Factory and router address's
    address _sushiSwapRouterAddress =
        0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;
    address _uniV2FactoryAddress = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    // address _sushiFactoryAddress = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;
    address _uniV3FactoryAddress = 0x1F98431c8aD98523631AE4a59f267346ea31F984;

    //Chainlink ERC20 address
    address swapToken = 0x514910771AF9Ca656af840dff83E8264EcF986CA;

    bytes32 _uniswapV2HexDem =
        hex"96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f";

    //Initialize array of Dex specifications
    bytes32[] _hexDems = [_uniswapV2HexDem, _uniswapV2HexDem];
    address[] _dexFactories = [_uniV2FactoryAddress, _uniV3FactoryAddress];
    bool[] _isUniV2 = [true, false];

    uint256 alphaXDivergenceThreshold = 3402823669209385000000000000000000; //0.00001

    address aggregatorV3Address = 0x169E633A2D1E6c10dD91238Ba11c4A708dfEF37C;

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

        limitOrderRouter = ILimitOrderRouter(
            limitOrderExecutor.LIMIT_ORDER_ROUTER()
        );
        //Wrapper contract to test internal functions
        limitOrderRouterWrapper = new LimitOrderRouter(
            0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
            0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48,
            address(limitOrderExecutor),
            1
        );

        orderBook = ILimitOrderBook(limitOrderExecutor.LIMIT_ORDER_ROUTER());
    }

    //================================================================
    //==================== Execution Tests ===========================
    //================================================================

    ///@notice Test to Execute a batch of Token To Weth Orders
    function testExecuteTokenToWethOrderBatch() public {
        cheatCodes.deal(address(swapHelper), MAX_UINT);
        cheatCodes.prank(tx.origin);
        limitOrderExecutor.checkIn();
        IERC20(DAI).approve(address(limitOrderExecutor), MAX_UINT);
        bytes32[] memory tokenToWethOrderBatch = placeNewMockTokenToWethBatch();

        uint256 cumulativeGasCompensation;
        //Make sure the orders have been placed
        for (uint256 i = 0; i < tokenToWethOrderBatch.length; ++i) {
            LimitOrderBook.LimitOrder memory order0 = orderBook
                .getLimitOrderById(tokenToWethOrderBatch[i]);
            cumulativeGasCompensation += order0.executionCredit;
            assert(order0.orderId != bytes32(0));
        }
        {
            ///@notice Cache the executor balances before execution.
            uint256 txOriginBalanceBefore = IERC20(WETH).balanceOf(tx.origin);
            uint256 gasCompensationBefore = address(tx.origin).balance;

            cheatCodes.prank(tx.origin);
            limitOrderRouter.executeLimitOrders(tokenToWethOrderBatch);
            uint256 gasCompensationAfter = address(tx.origin).balance;
            // check that the orders have been fufilled and removed
            for (uint256 i = 0; i < tokenToWethOrderBatch.length; ++i) {
                ///@notice Ensure tx.origin received the execution reward.
                assertGe(
                    IERC20(WETH).balanceOf(tx.origin),
                    txOriginBalanceBefore
                );

                ///@notice Ensure the upper and lower execution thresholds were paid to the beacon.
                assertGe(
                    gasCompensationAfter - gasCompensationBefore,
                    cumulativeGasCompensation
                );

                LimitOrderBook.OrderType orderType = orderBook
                    .addressToOrderIds(address(this), tokenToWethOrderBatch[i]);
                assert(orderType == LimitOrderBook.OrderType.FilledLimitOrder);
            }
        }
    }

    //Test fail case in execution with duplicate orderIds passed
    function testFailExecuteTokenToWethOrderBatch_DuplicateOrdersInExecution()
        public
    {
        cheatCodes.deal(address(swapHelper), MAX_UINT);
        cheatCodes.prank(tx.origin);
        limitOrderExecutor.checkIn();
        IERC20(DAI).approve(address(limitOrderExecutor), MAX_UINT);
        bytes32[]
            memory tokenToWethOrderBatch = placeNewMockTokenToWethBatchDuplicateOrderIds();

        //check that the orders have been placed
        for (uint256 i = 0; i < tokenToWethOrderBatch.length; ++i) {
            LimitOrderBook.LimitOrder memory order = orderBook
                .getLimitOrderById(tokenToWethOrderBatch[i]);

            assert(order.orderId != bytes32(0));
        }

        cheatCodes.prank(tx.origin);
        limitOrderRouter.executeLimitOrders(tokenToWethOrderBatch);
    }

    ///@notice Test to execute a single token to with order
    function testExecuteWethToTokenSingle() public {
        cheatCodes.deal(address(swapHelper), MAX_UINT);
        cheatCodes.deal(address(this), 500000000000 ether);
        cheatCodes.prank(tx.origin);
        limitOrderExecutor.checkIn();
        (bool depositSuccess, ) = address(WETH).call{value: 500000000000 ether}(
            abi.encodeWithSignature("deposit()")
        );

        require(depositSuccess, "failure when depositing ether into weth");

        IERC20(WETH).approve(address(limitOrderExecutor), MAX_UINT);
        //Create a new mock order
        LimitOrderBook.LimitOrder memory order = newMockOrder(
            WETH,
            DAI,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000000, //5000 WETH
            3000,
            0,
            0,
            MAX_U32
        );

        bytes32 orderId = placeMockOrder(order);
        bytes32[] memory orderBatch = new bytes32[](1);

        orderBatch[0] = orderId;
        //check that the orders have been placed
        for (uint256 i = 0; i < orderBatch.length; ++i) {
            LimitOrderBook.LimitOrder memory order0 = orderBook
                .getLimitOrderById(orderBatch[i]);

            assert(order0.orderId != bytes32(0));
        }
        cheatCodes.prank(tx.origin);
        limitOrderRouter.executeLimitOrders(orderBatch);

        // check that the orders have been fufilled and removed
        for (uint256 i = 0; i < orderBatch.length; ++i) {
            LimitOrderBook.OrderType orderType = orderBook.addressToOrderIds(
                address(this),
                orderId
            );
            assert(orderType == LimitOrderBook.OrderType.FilledLimitOrder);
        }
    }

    ///@notice Teas To execute a single token to Weth order Dai/Weth
    function testExecuteTokenToWethSingle(uint112 amountIn) public {
        bool run = false;
        if (amountIn < 1000000000000000000) {
            run = false;
        }
        if (run) {
            cheatCodes.prank(tx.origin);
        limitOrderExecutor.checkIn();
            cheatCodes.deal(address(swapHelper), MAX_UINT);
            swapHelper.swapEthForTokenWithUniV2(1000 ether, DAI);
            IERC20(DAI).approve(address(limitOrderExecutor), MAX_UINT);

            ///@notice Get the spot price of DAI/WETH
            (
                LimitOrderSwapRouter.SpotReserve memory spRes,

            ) = limitOrderExecutor.calculateV3SpotPrice(
                    DAI,
                    WETH,
                    500,
                    0x1F98431c8aD98523631AE4a59f267346ea31F984
                );

            ///@notice Slippage
            uint128 _95_PERCENT = 970000000000000000;

            ///@notice Decrement the amountExpectedOut by 95%
            uint112 amountOutMin = uint112(
                ConveyorMath.mul64U(
                    _95_PERCENT,
                    ConveyorMath.mul128U(spRes.spotPrice, amountIn)
                )
            );
            ///@notice Create a new mock order
            LimitOrderBook.LimitOrder memory order = newMockOrder(
                DAI,
                WETH,
                1,
                false,
                false,
                0,
                amountOutMin,
                5000000000000000000000, //5000 DAI
                3000,
                0,
                0,
                MAX_U32
            );

            //Place the order
            bytes32 orderId = placeMockOrder(order);

            bytes32[] memory orderBatch = new bytes32[](1);
            orderBatch[0] = orderId;

            //Get the fee
            uint128 fee = limitOrderExecutor.calculateFee(amountIn, USDC, WETH);

            //Get the minimum out amount expected
            //Should be fee
            uint256 balanceAfterMin = ConveyorMath.mul64U(
                ConveyorMath.div64x64(uint128(1), fee),
                amountOutMin
            );

            {
                ///@notice Cache the executor balances before execution.
                uint256 txOriginBalanceBefore = IERC20(WETH).balanceOf(
                    tx.origin
                );
                uint256 gasCompensationBefore = address(tx.origin).balance;
                uint256 cumulativeGasCompensation;
                ///@notice check that the orders have been placed
                for (uint256 i = 0; i < orderBatch.length; ++i) {
                    LimitOrderBook.LimitOrder memory order0 = orderBook
                        .getLimitOrderById(orderBatch[i]);
                    cumulativeGasCompensation += order0.executionCredit;
                    assert(order0.orderId != bytes32(0));
                }
                ///@notice Execute orders with an EOA.
                cheatCodes.prank(tx.origin);
                limitOrderRouter.executeLimitOrders(orderBatch);
                uint256 gasCompensationAfter = address(tx.origin).balance;
                // check that the orders have been fufilled and removed
                for (uint256 i = 0; i < orderBatch.length; ++i) {
                    LimitOrderBook.LimitOrder memory order0 = orderBook
                        .getLimitOrderById(orderBatch[i]);

                    ///@notice Ensure the user was compensated.
                    assertGe(balanceAfterMin, order.amountOutMin);
                    ///@notice Ensure the upper and lower execution thresholds were paid to the beacon.
                    assertEq(
                        gasCompensationAfter - gasCompensationBefore,
                        cumulativeGasCompensation
                    );

                    LimitOrderBook.OrderType orderType = orderBook
                        .addressToOrderIds(address(this), orderId);
                    assert(
                        orderType == LimitOrderBook.OrderType.FilledLimitOrder
                    );
                    ///@notice Ensure the order was removed from the contract.
                    assert(order0.orderId == bytes32(0));
                }
            }
        }
    }

    ///@notice Test to execute a batch of Weth to Token orders Weth/Dai
    function testExecuteWethToTokenOrderBatch() public {
        cheatCodes.deal(address(swapHelper), MAX_UINT);

        //Deposit weth to address(this)
        (bool depositSuccess, ) = address(WETH).call{value: 500000000 ether}(
            abi.encodeWithSignature("deposit()")
        );

        //require that the deposit was a success
        require(depositSuccess, "weth deposit failed");

        IERC20(WETH).approve(address(limitOrderExecutor), 5000000000 ether);
        cheatCodes.prank(tx.origin);
        limitOrderExecutor.checkIn();
        bytes32[] memory tokenToWethOrderBatch = placeNewMockWethToTokenBatch();
        uint256 cumulativeGasCompensation;
        //Make sure the orders have been placed
        for (uint256 i = 0; i < tokenToWethOrderBatch.length; ++i) {
            LimitOrderBook.LimitOrder memory order0 = orderBook
                .getLimitOrderById(tokenToWethOrderBatch[i]);
            cumulativeGasCompensation += order0.executionCredit;
            assert(order0.orderId != bytes32(0));
        }
        {
            ///@notice Cache the executor balances before execution.
            uint256 txOriginBalanceBefore = IERC20(WETH).balanceOf(tx.origin);
            uint256 gasCompensationBefore = address(tx.origin).balance;

            cheatCodes.prank(tx.origin);
            limitOrderRouter.executeLimitOrders(tokenToWethOrderBatch);
            uint256 gasCompensationAfter = address(tx.origin).balance;
            // check that the orders have been fufilled and removed
            for (uint256 i = 0; i < tokenToWethOrderBatch.length; ++i) {
                ///@notice Ensure tx.origin received the execution reward.
                assertGe(
                    IERC20(WETH).balanceOf(tx.origin),
                    txOriginBalanceBefore
                );

                ///@notice Ensure the upper and lower execution thresholds were paid to the beacon.
                assertGe(
                    gasCompensationAfter - gasCompensationBefore,
                    cumulativeGasCompensation
                );

                LimitOrderBook.OrderType orderType = orderBook
                    .addressToOrderIds(address(this), tokenToWethOrderBatch[i]);
                assert(orderType == LimitOrderBook.OrderType.FilledLimitOrder);
            }
        }
    }

    ///@notice Test to execute a single token to token order. Dai/Uni
    function testExecuteTokenToTokenSingle(uint80 amountIn) public {
        bool run = false;
        if (amountIn < 1000000000000000000) {
            run = false;
        }
        if (run) {
            cheatCodes.prank(tx.origin);
            limitOrderExecutor.checkIn();
            cheatCodes.deal(address(swapHelper), MAX_UINT);
            swapHelper.swapEthForTokenWithUniV2(1000 ether, DAI);
            IERC20(DAI).approve(address(limitOrderExecutor), MAX_UINT);
            ///@notice Get the spot price of DAI/WETH
            (
                LimitOrderSwapRouter.SpotReserve memory spRes,

            ) = limitOrderExecutor.calculateV3SpotPrice(
                    DAI,
                    UNI,
                    500,
                    0x1F98431c8aD98523631AE4a59f267346ea31F984
                );

            ///@notice Slippage
            uint128 _95_PERCENT = 970000000000000000;

            ///@notice Decrement the amountExpectedOut by 95%
            uint112 amountOutMin = uint112(
                ConveyorMath.mul64U(
                    _95_PERCENT,
                    ConveyorMath.mul128U(spRes.spotPrice, amountIn)
                )
            );

            //Get the fee
            uint128 fee = limitOrderExecutor.calculateFee(amountIn, USDC, WETH);

            //Get the minimum out amount expected
            //Should be fee
            uint256 balanceAfterMin = ConveyorMath.mul64U(
                ConveyorMath.div64x64(uint128(1), fee),
                amountOutMin
            );

            LimitOrderBook.LimitOrder memory order = newMockOrder(
                DAI,
                UNI,
                1,
                false,
                false,
                0,
                amountOutMin,
                amountIn, //5000 DAI
                3000,
                3000,
                0,
                MAX_U32
            );

            bytes32 orderId = placeMockOrder(order);

            bytes32[] memory orderBatch = new bytes32[](1);

            orderBatch[0] = orderId;
            for (uint256 i = 0; i < orderBatch.length; ++i) {
                LimitOrderBook.LimitOrder memory order0 = orderBook
                    .getLimitOrderById(orderBatch[i]);

                assert(order0.orderId != bytes32(0));
            }

            {
                ///@notice Cache the executor balances before execution.
                uint256 txOriginBalanceBefore = IERC20(WETH).balanceOf(
                    tx.origin
                );
                uint256 gasCompensationBefore = address(tx.origin).balance;
                uint256 cumulativeGasCompensation;
                ///@notice check that the orders have been placed
                for (uint256 i = 0; i < orderBatch.length; ++i) {
                    LimitOrderBook.LimitOrder memory order0 = orderBook
                        .getLimitOrderById(orderBatch[i]);
                    cumulativeGasCompensation += order0.executionCredit;
                    assert(order0.orderId != bytes32(0));
                }
                ///@notice Execute orders with an EOA.
                cheatCodes.prank(tx.origin);
                limitOrderRouter.executeLimitOrders(orderBatch);
                uint256 gasCompensationAfter = address(tx.origin).balance;
                // check that the orders have been fufilled and removed
                for (uint256 i = 0; i < orderBatch.length; ++i) {
                    LimitOrderBook.LimitOrder memory order0 = orderBook
                        .getLimitOrderById(orderBatch[i]);

                    ///@notice Ensure the user was compensated.
                    assertGe(balanceAfterMin, order.amountOutMin);
                    ///@notice Ensure the upper and lower execution thresholds were paid to the beacon.
                    assertEq(
                        gasCompensationAfter - gasCompensationBefore,
                        cumulativeGasCompensation
                    );

                    LimitOrderBook.OrderType orderType = orderBook
                        .addressToOrderIds(address(this), orderId);
                    assert(
                        orderType == LimitOrderBook.OrderType.FilledLimitOrder
                    );
                    ///@notice Ensure the order was removed from the contract.
                    assert(order0.orderId == bytes32(0));
                }
            }
        }
    }

    ///@notice Test To Execute a batch of Token to token orders Usdc/Uni
    function testExecuteTokenToTokenBatch() public {
        cheatCodes.deal(address(swapHelper), MAX_UINT);

        IERC20(USDC).approve(address(limitOrderExecutor), MAX_UINT);

        bytes32[]
            memory tokenToTokenOrderBatch = placeNewMockTokenToTokenBatch();
        cheatCodes.prank(tx.origin);
        limitOrderExecutor.checkIn();
        uint256 cumulativeGasCompensation;
        //Make sure the orders have been placed
        for (uint256 i = 0; i < tokenToTokenOrderBatch.length; ++i) {
            LimitOrderBook.LimitOrder memory order0 = orderBook
                .getLimitOrderById(tokenToTokenOrderBatch[i]);
            cumulativeGasCompensation += order0.executionCredit;
            assert(order0.orderId != bytes32(0));
        }
        {
            ///@notice Cache the executor balances before execution.
            uint256 txOriginBalanceBefore = IERC20(WETH).balanceOf(tx.origin);
            uint256 gasCompensationBefore = address(tx.origin).balance;

            cheatCodes.prank(tx.origin);
            limitOrderRouter.executeLimitOrders(tokenToTokenOrderBatch);
            uint256 gasCompensationAfter = address(tx.origin).balance;
            // check that the orders have been fufilled and removed
            for (uint256 i = 0; i < tokenToTokenOrderBatch.length; ++i) {
                ///@notice Ensure tx.origin received the execution reward.
                assertGe(
                    IERC20(WETH).balanceOf(tx.origin),
                    txOriginBalanceBefore
                );

                ///@notice Ensure the upper and lower execution thresholds were paid to the beacon.
                assertGe(
                    gasCompensationAfter - gasCompensationBefore,
                    cumulativeGasCompensation
                );

                LimitOrderBook.OrderType orderType = orderBook
                    .addressToOrderIds(
                        address(this),
                        tokenToTokenOrderBatch[i]
                    );
                assert(orderType == LimitOrderBook.OrderType.FilledLimitOrder);
            }
        }
    }

    ///@notice Test to execute a single weth to taxed order
    ///@notice Requires via-ir to compile test
    function testExecuteWethToTaxedTokenSingle(uint112 amountIn) public {
        bool run = false;
        if (amountIn < 1000000000000000000) {
            run = false;
        }
        if (run) {
            cheatCodes.prank(tx.origin);
            limitOrderExecutor.checkIn();
            cheatCodes.deal(address(swapHelper), MAX_UINT);

            address(WETH).call{value: amountIn}(
                abi.encodeWithSignature("deposit()")
            );

            IERC20(WETH).approve(address(limitOrderExecutor), MAX_UINT);

            ///@notice Get the spot price of DAI/WETH
            (
                LimitOrderSwapRouter.SpotReserve memory spRes,

            ) = limitOrderExecutor.calculateV2SpotPrice(
                    WETH,
                    TAXED_TOKEN,
                    _uniV2FactoryAddress,
                    _uniswapV2HexDem
                );

            ///@notice Slippage
            uint128 _95_PERCENT = 970000000000000000;

            ///@notice Decrement the amountExpectedOut by 95%
            uint112 amountOutMin = uint112(
                ConveyorMath.mul64U(
                    _95_PERCENT,
                    ConveyorMath.mul128U(spRes.spotPrice, amountIn)
                )
            );

            //Get the fee
            uint128 fee = limitOrderExecutor.calculateFee(amountIn, USDC, WETH);

            {
                //Get the minimum out amount expected
                //Should be fee
                uint256 balanceAfterMin = ConveyorMath.mul64U(
                    ConveyorMath.div64x64(uint128(1), fee),
                    amountOutMin
                );
                LimitOrderBook.LimitOrder memory order = newMockOrder(
                    WETH,
                    TAXED_TOKEN,
                    1,
                    false,
                    true,
                    0,
                    amountOutMin,
                    amountIn,
                    3000,
                    0,
                    0,
                    MAX_U32
                );

                bytes32 orderId = placeMockOrder(order);

                bytes32[] memory orderBatch = new bytes32[](1);

                orderBatch[0] = orderId;

                ///@notice Cache the executor balances before execution.
                uint256 txOriginBalanceBefore = IERC20(WETH).balanceOf(
                    tx.origin
                );
                uint256 gasCompensationBefore = address(tx.origin).balance;
                uint256 cumulativeGasCompensation;
                ///@notice check that the orders have been placed
                for (uint256 i = 0; i < orderBatch.length; ++i) {
                    LimitOrderBook.LimitOrder memory order0 = orderBook
                        .getLimitOrderById(orderBatch[i]);
                    cumulativeGasCompensation += order0.executionCredit;
                    assert(order0.orderId != bytes32(0));
                }
                ///@notice Execute orders with an EOA.
                cheatCodes.prank(tx.origin);
                limitOrderRouter.executeLimitOrders(orderBatch);
                uint256 gasCompensationAfter = address(tx.origin).balance;
                // check that the orders have been fufilled and removed
                for (uint256 i = 0; i < orderBatch.length; ++i) {
                    LimitOrderBook.LimitOrder memory order0 = orderBook
                        .getLimitOrderById(orderBatch[i]);

                    ///@notice Ensure the user was compensated.
                    assertGe(balanceAfterMin, order.amountOutMin);
                    ///@notice Ensure the upper and lower execution thresholds were paid to the beacon.
                    assertEq(
                        gasCompensationAfter - gasCompensationBefore,
                        cumulativeGasCompensation
                    );

                    LimitOrderBook.OrderType orderType = orderBook
                        .addressToOrderIds(address(this), orderId);
                    assert(
                        orderType == LimitOrderBook.OrderType.FilledLimitOrder
                    );
                    ///@notice Ensure the order was removed from the contract.
                    assert(order0.orderId == bytes32(0));
                }
            }
        }
    }

    ///@notice Test to execute a batch of weth to taxed token orders
    function testExecuteWethToTaxedTokenBatch() public {
        cheatCodes.prank(tx.origin);
        limitOrderExecutor.checkIn();
        cheatCodes.deal(address(swapHelper), MAX_UINT);
        cheatCodes.deal(address(this), 500000000000 ether);
        (bool depositSuccess, ) = address(WETH).call{value: 500000000000 ether}(
            abi.encodeWithSignature("deposit()")
        );

        require(depositSuccess, "failure when depositing ether into weth");

        IERC20(WETH).approve(address(limitOrderExecutor), MAX_UINT);

        bytes32[] memory wethToTaxedOrderBatch = placeNewMockWethToTaxedBatch();

        uint256 cumulativeGasCompensation;
        //Make sure the orders have been placed
        for (uint256 i = 0; i < wethToTaxedOrderBatch.length; ++i) {
            LimitOrderBook.LimitOrder memory order0 = orderBook
                .getLimitOrderById(wethToTaxedOrderBatch[i]);
            cumulativeGasCompensation += order0.executionCredit;
            assert(order0.orderId != bytes32(0));
        }
        {
            ///@notice Cache the executor balances before execution.
            uint256 txOriginBalanceBefore = IERC20(WETH).balanceOf(tx.origin);
            uint256 gasCompensationBefore = address(tx.origin).balance;

            cheatCodes.prank(tx.origin);
            limitOrderRouter.executeLimitOrders(wethToTaxedOrderBatch);
            uint256 gasCompensationAfter = address(tx.origin).balance;
            // check that the orders have been fufilled and removed
            for (uint256 i = 0; i < wethToTaxedOrderBatch.length; ++i) {
                ///@notice Ensure tx.origin received the execution reward.
                assertGe(
                    IERC20(WETH).balanceOf(tx.origin),
                    txOriginBalanceBefore
                );

                ///@notice Ensure the upper and lower execution thresholds were paid to the beacon.
                assertGe(
                    gasCompensationAfter - gasCompensationBefore,
                    cumulativeGasCompensation
                );

                LimitOrderBook.OrderType orderType = orderBook
                    .addressToOrderIds(address(this), wethToTaxedOrderBatch[i]);
                assert(orderType == LimitOrderBook.OrderType.FilledLimitOrder);
            }
        }
    }

    ///@notice Test to execute a single taxed to token order Taxed_token/Weth
    function testExecuteTaxedTokenToWethSingle() public {
        cheatCodes.prank(tx.origin);
        limitOrderExecutor.checkIn();
        cheatCodes.deal(address(swapHelper), MAX_UINT);
        swapHelper.swapEthForTokenWithUniV2(1000 ether, TAXED_TOKEN);

        IERC20(TAXED_TOKEN).approve(address(limitOrderExecutor), MAX_UINT);

        LimitOrderBook.LimitOrder memory order = newMockOrder(
            TAXED_TOKEN,
            WETH,
            1,
            false,
            true,
            4000,
            1,
            20000000000000000, //2,000,000
            3000,
            0,
            0,
            MAX_U32
        );
        //Place the order
        bytes32 orderId = placeMockOrder(order);

        bytes32[] memory orderBatch = new bytes32[](1);
        orderBatch[0] = orderId;

        {
            ///@notice Cache the executor balances before execution.
            uint256 txOriginBalanceBefore = IERC20(WETH).balanceOf(tx.origin);

            uint256 cumulativeGasCompensation = 0;
            ///@notice check that the orders have been placed
            for (uint256 i = 0; i < orderBatch.length; ++i) {
                LimitOrderBook.LimitOrder memory order0 = orderBook
                    .getLimitOrderById(orderBatch[i]);
                cumulativeGasCompensation += order0.executionCredit;
                assert(order0.orderId != bytes32(0));
            }
            uint256 gasCompensationBefore = address(tx.origin).balance;
            ///@notice Execute orders with an EOA.
            cheatCodes.prank(tx.origin);
            limitOrderRouter.executeLimitOrders(orderBatch);
            uint256 gasCompensationAfter = address(tx.origin).balance;
            uint256 txOriginBalanceAfter = IERC20(WETH).balanceOf(tx.origin);
            // check that the orders have been fufilled and removed
            for (uint256 i = 0; i < orderBatch.length; ++i) {
                ///@notice Ensure the upper and lower execution thresholds were paid to the beacon.
                assertGe(
                    gasCompensationAfter - gasCompensationBefore,
                    cumulativeGasCompensation
                );
                assertGe(txOriginBalanceAfter, txOriginBalanceBefore);

                LimitOrderBook.OrderType orderType = orderBook
                    .addressToOrderIds(address(this), orderId);
                assert(orderType == LimitOrderBook.OrderType.FilledLimitOrder);
            }
        }
    }

    ///@notice Test to execute a batch of Taxed to token orders
    function testExecuteTaxedTokenToWethBatch() public {
        cheatCodes.prank(tx.origin);
        limitOrderExecutor.checkIn();
        cheatCodes.deal(address(swapHelper), MAX_UINT);

        IERC20(TAXED_TOKEN).approve(address(limitOrderExecutor), MAX_UINT);

        bytes32[]
            memory tokenToWethOrderBatch = placeNewMockTokenToWethTaxedBatch();

        uint256 cumulativeGasCompensation;
        //Make sure the orders have been placed
        for (uint256 i = 0; i < tokenToWethOrderBatch.length; ++i) {
            LimitOrderBook.LimitOrder memory order0 = orderBook
                .getLimitOrderById(tokenToWethOrderBatch[i]);
            cumulativeGasCompensation += order0.executionCredit;
            assert(order0.orderId != bytes32(0));
        }
        {
            ///@notice Cache the executor balances before execution.
            uint256 txOriginBalanceBefore = IERC20(WETH).balanceOf(tx.origin);
            uint256 gasCompensationBefore = address(tx.origin).balance;

            cheatCodes.prank(tx.origin);
            limitOrderRouter.executeLimitOrders(tokenToWethOrderBatch);
            uint256 gasCompensationAfter = address(tx.origin).balance;
            // check that the orders have been fufilled and removed
            for (uint256 i = 0; i < tokenToWethOrderBatch.length; ++i) {
                ///@notice Ensure tx.origin received the execution reward.
                assertGe(
                    IERC20(WETH).balanceOf(tx.origin),
                    txOriginBalanceBefore
                );

                ///@notice Ensure the upper and lower execution thresholds were paid to the beacon.
                assertGe(
                    gasCompensationAfter - gasCompensationBefore,
                    cumulativeGasCompensation
                );

                LimitOrderBook.OrderType orderType = orderBook
                    .addressToOrderIds(address(this), tokenToWethOrderBatch[i]);
                assert(orderType == LimitOrderBook.OrderType.FilledLimitOrder);
            }
        }
    }

    ///@notice Test to execute a single Token To Taxed order
    function testExecuteTokenToTaxedTokenSingle() public {
        cheatCodes.prank(tx.origin);
        limitOrderExecutor.checkIn();
        cheatCodes.deal(address(swapHelper), MAX_UINT);
        swapHelper.swapEthForTokenWithUniV2(1000 ether, DAI);

        IERC20(DAI).approve(address(limitOrderExecutor), MAX_UINT);
        LimitOrderBook.LimitOrder memory order = newMockOrder(
            DAI,
            TAXED_TOKEN,
            1,
            false,
            true,
            0,
            1,
            20000000000000000000000, //20,000
            3000,
            3000,
            0,
            MAX_U32
        );

        //Place the order
        bytes32 orderId = placeMockOrder(order);

        bytes32[] memory orderBatch = new bytes32[](1);
        orderBatch[0] = orderId;

        {
            ///@notice Cache the executor balances before execution.
            uint256 txOriginBalanceBefore = IERC20(WETH).balanceOf(tx.origin);

            uint256 cumulativeGasCompensation = 0;
            ///@notice check that the orders have been placed
            for (uint256 i = 0; i < orderBatch.length; ++i) {
                LimitOrderBook.LimitOrder memory order0 = orderBook
                    .getLimitOrderById(orderBatch[i]);
                cumulativeGasCompensation += order0.executionCredit;
                assert(order0.orderId != bytes32(0));
            }
            uint256 gasCompensationBefore = address(tx.origin).balance;
            ///@notice Execute orders with an EOA.
            cheatCodes.prank(tx.origin);
            limitOrderRouter.executeLimitOrders(orderBatch);
            uint256 gasCompensationAfter = address(tx.origin).balance;
            uint256 txOriginBalanceAfter = IERC20(WETH).balanceOf(tx.origin);
            // check that the orders have been fufilled and removed
            for (uint256 i = 0; i < orderBatch.length; ++i) {
                ///@notice Ensure the upper and lower execution thresholds were paid to the beacon.
                assertGe(
                    gasCompensationAfter - gasCompensationBefore,
                    cumulativeGasCompensation
                );
                assertGe(txOriginBalanceAfter, txOriginBalanceBefore);

                LimitOrderBook.OrderType orderType = orderBook
                    .addressToOrderIds(address(this), orderId);
                assert(orderType == LimitOrderBook.OrderType.FilledLimitOrder);
            }
        }
    }

    ///@notice Taxed Token to dai single test
    function testExecuteTaxedTokenToTokenSingle() public {
        cheatCodes.prank(tx.origin);
        limitOrderExecutor.checkIn();
        cheatCodes.deal(address(swapHelper), MAX_UINT);
        swapHelper.swapEthForTokenWithUniV2(100 ether, TAXED_TOKEN);

        IERC20(TAXED_TOKEN).approve(address(limitOrderExecutor), MAX_UINT);

        LimitOrderBook.LimitOrder memory order = newMockOrder(
            TAXED_TOKEN,
            DAI,
            1,
            false,
            true,
            1000,
            1,
            200000000000000, //2,000,000
            3000,
            3000,
            0,
            MAX_U32
        );

        //Place the order
        bytes32 orderId = placeMockOrder(order);

        bytes32[] memory orderBatch = new bytes32[](1);
        orderBatch[0] = orderId;

        {
            ///@notice Cache the executor balances before execution.
            uint256 txOriginBalanceBefore = IERC20(WETH).balanceOf(tx.origin);

            uint256 cumulativeGasCompensation = 0;
            ///@notice check that the orders have been placed
            for (uint256 i = 0; i < orderBatch.length; ++i) {
                LimitOrderBook.LimitOrder memory order0 = orderBook
                    .getLimitOrderById(orderBatch[i]);
                cumulativeGasCompensation += order0.executionCredit;
                assert(order0.orderId != bytes32(0));
            }
            uint256 gasCompensationBefore = address(tx.origin).balance;
            ///@notice Execute orders with an EOA.
            cheatCodes.prank(tx.origin);
            limitOrderRouter.executeLimitOrders(orderBatch);
            uint256 gasCompensationAfter = address(tx.origin).balance;
            uint256 txOriginBalanceAfter = IERC20(WETH).balanceOf(tx.origin);
            // check that the orders have been fufilled and removed
            for (uint256 i = 0; i < orderBatch.length; ++i) {
                ///@notice Ensure the upper and lower execution thresholds were paid to the beacon.
                assertGe(
                    gasCompensationAfter - gasCompensationBefore,
                    cumulativeGasCompensation
                );
                assertGe(txOriginBalanceAfter, txOriginBalanceBefore);

                LimitOrderBook.OrderType orderType = orderBook
                    .addressToOrderIds(address(this), orderId);
                assert(orderType == LimitOrderBook.OrderType.FilledLimitOrder);
            }
        }
    }

    ///@notice Test to execute a batch of taxed token to token orders
    function testExecuteTaxedTokenToTokenBatch() public {
        cheatCodes.prank(tx.origin);
        limitOrderExecutor.checkIn();
        cheatCodes.deal(address(swapHelperUniV2), MAX_UINT);
        swapHelperUniV2.swapEthForTokenWithUniV2(10000 ether, TAXED_TOKEN);

        IERC20(TAXED_TOKEN).approve(address(limitOrderExecutor), MAX_UINT);

        bytes32[] memory orderBatch = placeNewMockTaxedToTokenBatch();

        uint256 cumulativeGasCompensation;
        //Make sure the orders have been placed
        for (uint256 i = 0; i < orderBatch.length; ++i) {
            LimitOrderBook.LimitOrder memory order0 = orderBook
                .getLimitOrderById(orderBatch[i]);
            cumulativeGasCompensation += order0.executionCredit;
            assert(order0.orderId != bytes32(0));
        }
        {
            ///@notice Cache the executor balances before execution.
            uint256 txOriginBalanceBefore = IERC20(WETH).balanceOf(tx.origin);
            uint256 gasCompensationBefore = address(tx.origin).balance;

            cheatCodes.prank(tx.origin);
            limitOrderRouter.executeLimitOrders(orderBatch);
            uint256 gasCompensationAfter = address(tx.origin).balance;
            // check that the orders have been fufilled and removed
            for (uint256 i = 0; i < orderBatch.length; ++i) {
                ///@notice Ensure tx.origin received the execution reward.
                assertGe(
                    IERC20(WETH).balanceOf(tx.origin),
                    txOriginBalanceBefore
                );

                ///@notice Ensure the upper and lower execution thresholds were paid to the beacon.
                assertGe(
                    gasCompensationAfter - gasCompensationBefore,
                    cumulativeGasCompensation
                );

                LimitOrderBook.OrderType orderType = orderBook
                    .addressToOrderIds(address(this), orderBatch[i]);
                assert(orderType == LimitOrderBook.OrderType.FilledLimitOrder);
            }
        }
    }

    ///@notice Test to execute a batch of taxed token to taxed token orders
    function testExecuteTaxedTokenToTaxedTokenBatch() public {
        cheatCodes.prank(tx.origin);
        limitOrderExecutor.checkIn();
        cheatCodes.deal(address(swapHelperUniV2), MAX_UINT);
        swapHelperUniV2.swapEthForTokenWithUniV2(10000 ether, TAXED_TOKEN);

        IERC20(TAXED_TOKEN).approve(address(limitOrderExecutor), MAX_UINT);

        bytes32[] memory orderBatch = placeNewMockTaxedToTaxedTokenBatch();
        uint256 cumulativeGasCompensation;
        //Make sure the orders have been placed
        for (uint256 i = 0; i < orderBatch.length; ++i) {
            LimitOrderBook.LimitOrder memory order0 = orderBook
                .getLimitOrderById(orderBatch[i]);
            cumulativeGasCompensation += order0.executionCredit;
            assert(order0.orderId != bytes32(0));
        }
        {
            ///@notice Cache the executor balances before execution.
            uint256 txOriginBalanceBefore = IERC20(WETH).balanceOf(tx.origin);
            uint256 gasCompensationBefore = address(tx.origin).balance;

            cheatCodes.prank(tx.origin);
            limitOrderRouter.executeLimitOrders(orderBatch);
            uint256 gasCompensationAfter = address(tx.origin).balance;
            // check that the orders have been fufilled and removed
            for (uint256 i = 0; i < orderBatch.length; ++i) {
                ///@notice Ensure tx.origin received the execution reward.
                assertGe(
                    IERC20(WETH).balanceOf(tx.origin),
                    txOriginBalanceBefore
                );

                ///@notice Ensure the upper and lower execution thresholds were paid to the beacon.
                assertGe(
                    gasCompensationAfter - gasCompensationBefore,
                    cumulativeGasCompensation
                );

                LimitOrderBook.OrderType orderType = orderBook
                    .addressToOrderIds(address(this), orderBatch[i]);
                assert(orderType == LimitOrderBook.OrderType.FilledLimitOrder);
            }
        }
    }

    ///@notice Test to execute a single taxed token to taxed token order
    function testExecuteTaxedTokenToTaxedTokenSingle() public {
        cheatCodes.prank(tx.origin);
        limitOrderExecutor.checkIn();
        cheatCodes.deal(address(swapHelper), MAX_UINT);
        swapHelper.swapEthForTokenWithUniV2(1000 ether, TAXED_TOKEN);

        IERC20(TAXED_TOKEN).approve(address(limitOrderExecutor), MAX_UINT);

        LimitOrderBook.LimitOrder memory order = newMockOrder(
            TAXED_TOKEN,
            TAXED_TOKEN_1,
            1,
            false,
            true,
            3000,
            1,
            2000000000000000000000000, //2,000,000
            3000,
            3000,
            0,
            MAX_U32
        );

        //Place the order
        bytes32 orderId = placeMockOrder(order);

        bytes32[] memory orderBatch = new bytes32[](1);
        orderBatch[0] = orderId;

        {
            ///@notice Cache the executor balances before execution.
            uint256 txOriginBalanceBefore = IERC20(WETH).balanceOf(tx.origin);

            uint256 cumulativeGasCompensation = 0;
            ///@notice check that the orders have been placed
            for (uint256 i = 0; i < orderBatch.length; ++i) {
                LimitOrderBook.LimitOrder memory order0 = orderBook
                    .getLimitOrderById(orderBatch[i]);
                cumulativeGasCompensation += order0.executionCredit;
                assert(order0.orderId != bytes32(0));
            }
            uint256 gasCompensationBefore = address(tx.origin).balance;
            ///@notice Execute orders with an EOA.
            cheatCodes.prank(tx.origin);
            limitOrderRouter.executeLimitOrders(orderBatch);
            uint256 gasCompensationAfter = address(tx.origin).balance;
            uint256 txOriginBalanceAfter = IERC20(WETH).balanceOf(tx.origin);
            // check that the orders have been fufilled and removed
            for (uint256 i = 0; i < orderBatch.length; ++i) {
                ///@notice Ensure the upper and lower execution thresholds were paid to the beacon.
                assertGe(
                    gasCompensationAfter - gasCompensationBefore,
                    cumulativeGasCompensation
                );
                assertGe(txOriginBalanceAfter, txOriginBalanceBefore);

                LimitOrderBook.OrderType orderType = orderBook
                    .addressToOrderIds(address(this), orderId);
                assert(orderType == LimitOrderBook.OrderType.FilledLimitOrder);
            }
        }
    }

    //================================================================
    //==================== Execution Fail Tests ======================
    //================================================================

    function testFailExecuteTokenToTokenBatch_InvalidNonEOAStoplossExecution()
        public
    {
        cheatCodes.prank(tx.origin);
        limitOrderExecutor.checkIn();
        cheatCodes.deal(address(swapHelper), MAX_UINT);

        IERC20(USDC).approve(address(limitOrderExecutor), MAX_UINT);

        bytes32[]
            memory tokenToTokenOrderBatch = placeNewMockTokenToTokenStoplossBatch();

        //check that the orders have been placed
        for (uint256 i = 0; i < tokenToTokenOrderBatch.length; ++i) {
            LimitOrderBook.LimitOrder memory order = orderBook
                .getLimitOrderById(tokenToTokenOrderBatch[i]);

            assert(order.orderId != bytes32(0));
        }

        //Don't prank tx.origin should revert
        limitOrderRouter.executeLimitOrders(tokenToTokenOrderBatch);

        // check that the orders have been fufilled and removed
        for (uint256 i = 0; i < tokenToTokenOrderBatch.length; ++i) {
            LimitOrderBook.LimitOrder memory order = orderBook
                .getLimitOrderById(tokenToTokenOrderBatch[i]);
            assert(order.orderId == bytes32(0));
        }
    }

    ///@notice Test fail Execute a batch of Token to token with revert on duplicate orderIds in batch
    function testFailExecuteTokenToTokenBatch_DuplicateOrdersInExecution()
        public
    {
        cheatCodes.prank(tx.origin);
        limitOrderExecutor.checkIn();
        cheatCodes.deal(address(swapHelper), MAX_UINT);

        IERC20(USDC).approve(address(limitOrderExecutor), MAX_UINT);

        bytes32[]
            memory tokenToTokenOrderBatch = placeNewMockTokenToTokenBatchDuplicateOrderIds();

        //check that the orders have been placed
        for (uint256 i = 0; i < tokenToTokenOrderBatch.length; ++i) {
            LimitOrderBook.LimitOrder memory order = orderBook
                .getLimitOrderById(tokenToTokenOrderBatch[i]);

            assert(order.orderId != bytes32(0));
        }

        cheatCodes.prank(tx.origin);
        limitOrderRouter.executeLimitOrders(tokenToTokenOrderBatch);

        // check that the orders have been fufilled and removed
        for (uint256 i = 0; i < tokenToTokenOrderBatch.length; ++i) {
            LimitOrderBook.LimitOrder memory order = orderBook
                .getLimitOrderById(tokenToTokenOrderBatch[i]);
            assert(order.orderId == bytes32(0));
        }
    }

    //Test fail case in execution with duplicate orderIds passed
    function testFailExecuteTokenToWethOrderBatch_InvalidNonEOAStoplossExecution()
        public
    {
        cheatCodes.prank(tx.origin);
        limitOrderExecutor.checkIn();
        cheatCodes.deal(address(swapHelper), MAX_UINT);

        IERC20(DAI).approve(address(limitOrderExecutor), MAX_UINT);
        bytes32[]
            memory tokenToWethOrderBatch = placeNewMockTokenToWethBatchStoploss();

        //check that the orders have been placed
        for (uint256 i = 0; i < tokenToWethOrderBatch.length; ++i) {
            LimitOrderBook.LimitOrder memory order = orderBook
                .getLimitOrderById(tokenToWethOrderBatch[i]);

            assert(order.orderId != bytes32(0));
        }

        //Dont prank tx.origin should revert with stoploss orders.
        limitOrderRouter.executeLimitOrders(tokenToWethOrderBatch);

        // check that the orders have been fufilled and removed
        for (uint256 i = 0; i < tokenToWethOrderBatch.length; ++i) {
            LimitOrderBook.LimitOrder memory order = orderBook
                .getLimitOrderById(tokenToWethOrderBatch[i]);
            assert(order.orderId == bytes32(0));
        }
    }

    ///@notice Test to check fail case if orderIds length is 0
    function testFailExecuteOrders_InvalidCalldata() public {
        bytes32[] memory emptyIdArray = new bytes32[](0);
        cheatCodes.prank(tx.origin);
        limitOrderExecutor.checkIn();
        cheatCodes.prank(tx.origin);
        limitOrderRouter.executeLimitOrders(emptyIdArray);
    }

    ///@notice Test to check fail case if orderId is not in the state of contract
    function testFailExecuteOrders_OrderDoesNotExist() public {
        cheatCodes.prank(tx.origin);
        limitOrderExecutor.checkIn();
        bytes32[] memory orderIds = new bytes32[](1);
        orderIds[0] = bytes32(0);
        cheatCodes.prank(tx.origin);
        limitOrderRouter.executeLimitOrders(orderIds);
    }

    function testFailExecuteOrders_ExecutorNotCheckedIn() public {
        bytes32[] memory orderIds = new bytes32[](1);
        orderIds[0] = bytes32(0);
        limitOrderRouter.executeLimitOrders(orderIds);
    }

    receive() external payable {}

    //================================================================
    //======================= Helper functions =======================
    //================================================================

    function newMockStoplossOrder(
        address tokenIn,
        address tokenOut,
        uint128 price,
        bool buy,
        bool stoploss,
        bool taxed,
        uint16 taxIn,
        uint112 amountOutMin,
        uint112 quantity,
        uint16 feeIn,
        uint16 feeOut,
        uint32 lastRefreshTimestamp,
        uint32 expirationTimestamp
    ) internal view returns (LimitOrderBook.LimitOrder memory order) {
        //Initialize mock order
        order = LimitOrderBook.LimitOrder({
            stoploss: stoploss,
            buy: buy,
            taxed: taxed,
            lastRefreshTimestamp: lastRefreshTimestamp,
            expirationTimestamp: expirationTimestamp,
            feeIn: feeIn,
            feeOut: feeOut,
            executionCredit: 0,
            taxIn: taxIn,
            price: price,
            amountOutMin: amountOutMin,
            quantity: quantity,
            owner: msg.sender,
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            orderId: bytes32(0)
        });
    }

    function newMockOrder(
        address tokenIn,
        address tokenOut,
        uint128 price,
        bool buy,
        bool taxed,
        uint16 taxIn,
        uint112 amountOutMin,
        uint112 quantity,
        uint16 feeIn,
        uint16 feeOut,
        uint32 lastRefreshTimestamp,
        uint32 expirationTimestamp
    ) internal view returns (LimitOrderBook.LimitOrder memory order) {
        //Initialize mock order
        order = LimitOrderBook.LimitOrder({
            stoploss: false,
            buy: buy,
            taxed: taxed,
            lastRefreshTimestamp: lastRefreshTimestamp,
            expirationTimestamp: expirationTimestamp,
            feeIn: feeIn,
            executionCredit: 0,
            feeOut: feeOut,
            taxIn: taxIn,
            price: price,
            amountOutMin: amountOutMin,
            quantity: quantity,
            owner: msg.sender,
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

    function placeNewMockTokenToWethBatch()
        internal
        returns (bytes32[] memory)
    {
        swapHelper.swapEthForTokenWithUniV2(1000 ether, DAI);

        LimitOrderBook.LimitOrder memory order1 = newMockOrder(
            DAI,
            WETH,
            1,
            false,
            false,
            0,
            1000000000000000000,
            5000000000000000000000, //5000 DAI
            3000,
            300,
            500,
            MAX_U32
        );

        LimitOrderBook.LimitOrder memory order2 = newMockOrder(
            DAI,
            WETH,
            1,
            false,
            false,
            0,
            1000000000000000000,
            5000000000000000000001, //5001 DAI
            3000,
            300,
            500,
            MAX_U32
        );
        LimitOrderBook.LimitOrder memory order3 = newMockOrder(
            DAI,
            WETH,
            1,
            false,
            false,
            0,
            1000000000000000000,
            5000000000000000000002, //5002 DAI
            3000,
            300,
            500,
            MAX_U32
        );
        LimitOrderBook.LimitOrder memory order4 = newMockOrder(
            DAI,
            WETH,
            1,
            false,
            false,
            0,
            1000000000000000000,
            5000000000000000000003, //5003 DAI
            3000,
            300,
            500,
            MAX_U32
        );
        LimitOrderBook.LimitOrder[]
            memory orderBatch = new LimitOrderBook.LimitOrder[](4);
        orderBatch[0] = order1;
        orderBatch[1] = order2;
        orderBatch[2] = order3;
        orderBatch[3] = order4;
        return placeMultipleMockOrder(orderBatch);
    }

    function placeNewMockTokenToWethBatchDuplicateOrderIds()
        internal
        returns (bytes32[] memory)
    {
        swapHelper.swapEthForTokenWithUniV2(1000 ether, DAI);

        LimitOrderBook.LimitOrder memory order1 = newMockOrder(
            DAI,
            WETH,
            1,
            false,
            false,
            0,
            1000000000000000000,
            5000000000000000000000, //5000 DAI
            3000,
            0,
            0,
            MAX_U32
        );

        LimitOrderBook.LimitOrder memory order2 = newMockOrder(
            DAI,
            WETH,
            1,
            false,
            false,
            0,
            1000000000000000000,
            5000000000000000000001, //5001 DAI
            3000,
            3000,
            0,
            MAX_U32
        );
        LimitOrderBook.LimitOrder memory order3 = newMockOrder(
            DAI,
            WETH,
            1,
            false,
            false,
            0,
            1000000000000000000,
            5000000000000000000002, //5002 DAI
            3000,
            3000,
            0,
            MAX_U32
        );
        LimitOrderBook.LimitOrder memory order4 = newMockOrder(
            DAI,
            WETH,
            1,
            false,
            false,
            0,
            1000000000000000000,
            5000000000000000000003, //5003 DAI
            3000,
            3000,
            0,
            MAX_U32
        );
        LimitOrderBook.LimitOrder[]
            memory orderBatch = new LimitOrderBook.LimitOrder[](4);
        orderBatch[0] = order1;
        orderBatch[1] = order2;
        orderBatch[2] = order3;
        orderBatch[3] = order4;
        bytes32[] memory orderIds = new bytes32[](5);
        bytes32[] memory returnIds = placeMultipleMockOrder(orderBatch);
        orderIds[0] = returnIds[0];
        orderIds[1] = returnIds[1];
        orderIds[2] = returnIds[2];
        orderIds[3] = returnIds[3];
        orderIds[4] = returnIds[0]; //Add a duplicate orderId to the batch
        return orderIds;
    }

    function placeNewMockTokenToWethTaxedBatch()
        internal
        returns (bytes32[] memory)
    {
        swapHelper.swapEthForTokenWithUniV2(1000 ether, TAXED_TOKEN);

        LimitOrderBook.LimitOrder memory order1 = newMockOrder(
            TAXED_TOKEN,
            WETH,
            1,
            false,
            true,
            4000,
            1,
            20000000000000000, //2,000,000
            3000,
            0,
            0,
            MAX_U32
        );

        LimitOrderBook.LimitOrder memory order2 = newMockOrder(
            TAXED_TOKEN,
            WETH,
            1,
            false,
            true,
            4000,
            1,
            20000000000000000, //2,000,000
            3000,
            0,
            0,
            MAX_U32
        );
        LimitOrderBook.LimitOrder memory order3 = newMockOrder(
            TAXED_TOKEN,
            WETH,
            1,
            false,
            true,
            4000,
            1,
            20000000000000000, //2,000,000
            3000,
            0,
            0,
            MAX_U32
        );
        LimitOrderBook.LimitOrder memory order4 = newMockOrder(
            TAXED_TOKEN,
            WETH,
            1,
            false,
            true,
            4000,
            1,
            20000000000000000, //2,000,000
            3000,
            0,
            0,
            MAX_U32
        );

        LimitOrderBook.LimitOrder[]
            memory orderBatch = new LimitOrderBook.LimitOrder[](4);
        orderBatch[0] = order1;
        orderBatch[1] = order2;
        orderBatch[2] = order3;
        orderBatch[3] = order4;
        return placeMultipleMockOrder(orderBatch);
    }

    function placeNewMockTokenToWethBatch_InvalidBatchOrdering()
        internal
        returns (bytes32[] memory)
    {
        swapHelper.swapEthForTokenWithUniV2(1000 ether, DAI);

        LimitOrderBook.LimitOrder memory order1 = newMockOrder(
            DAI,
            WETH,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000000, //5000 DAI
            3000,
            0,
            0,
            MAX_U32
        );

        LimitOrderBook.LimitOrder memory order2 = newMockOrder(
            DAI,
            WETH,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000003, //5003 DAI
            3000,
            0,
            0,
            MAX_U32
        );
        LimitOrderBook.LimitOrder memory order3 = newMockOrder(
            DAI,
            WETH,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000002, //5002 DAI
            3000,
            0,
            0,
            MAX_U32
        );

        LimitOrderBook.LimitOrder[]
            memory orderBatch = new LimitOrderBook.LimitOrder[](3);
        orderBatch[0] = order1;
        orderBatch[1] = order2;
        orderBatch[2] = order3;

        return placeMultipleMockOrder(orderBatch);
    }

    function newMockTokenToWethBatch_InvalidBatchOrdering()
        internal
        returns (LimitOrderBook.LimitOrder[] memory)
    {
        swapHelper.swapEthForTokenWithUniV2(1000 ether, DAI);

        LimitOrderBook.LimitOrder memory order1 = newMockOrder(
            DAI,
            WETH,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000000, //5000 DAI
            3000,
            0,
            0,
            MAX_U32
        );

        LimitOrderBook.LimitOrder memory order2 = newMockOrder(
            DAI,
            WETH,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000003, //5003 DAI
            3000,
            0,
            0,
            MAX_U32
        );
        LimitOrderBook.LimitOrder memory order3 = newMockOrder(
            DAI,
            WETH,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000002, //5002 DAI
            3000,
            0,
            0,
            MAX_U32
        );

        LimitOrderBook.LimitOrder[]
            memory orderBatch = new LimitOrderBook.LimitOrder[](3);
        orderBatch[0] = order1;
        orderBatch[1] = order2;
        orderBatch[2] = order3;

        return orderBatch;
    }

    function placeNewMockTokenToWethBatch_IncongruentTokenIn()
        internal
        returns (bytes32[] memory)
    {
        swapHelper.swapEthForTokenWithUniV2(1000 ether, UNI);
        swapHelper.swapEthForTokenWithUniV2(1000 ether, USDC);

        LimitOrderBook.LimitOrder memory order1 = newMockOrder(
            DAI,
            WETH,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000000, //5000 DAI
            3000,
            0,
            0,
            MAX_U32
        );

        LimitOrderBook.LimitOrder memory order2 = newMockOrder(
            USDC,
            WETH,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000001, //5001 DAI
            3000,
            0,
            0,
            MAX_U32
        );
        LimitOrderBook.LimitOrder memory order3 = newMockOrder(
            DAI,
            WETH,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000002, //5002 DAI
            3000,
            0,
            0,
            MAX_U32
        );
        LimitOrderBook.LimitOrder[]
            memory orderBatch = new LimitOrderBook.LimitOrder[](3);
        orderBatch[0] = order1;
        orderBatch[1] = order2;
        bytes32[] memory mockOrderOrderIds = placeMultipleMockOrder(orderBatch);
        //place incongruent token order
        bytes32 mockOrderId = placeMockOrder(order3);

        bytes32[] memory orderIds = new bytes32[](3);
        orderIds[0] = mockOrderOrderIds[0];
        orderIds[1] = mockOrderOrderIds[1];
        orderIds[2] = mockOrderId;

        return orderIds;
    }

    function placeNewMockTokenToWethBatch_IncongruentStoploss()
        internal
        returns (LimitOrderBook.LimitOrder[] memory)
    {
        swapHelper.swapEthForTokenWithUniV2(1000 ether, UNI);
        swapHelper.swapEthForTokenWithUniV2(1000 ether, USDC);

        LimitOrderBook.LimitOrder memory order1 = newMockStoplossOrder(
            DAI,
            WETH,
            1,
            false,
            true,
            false,
            0,
            1,
            5000000000000000000000, //5000 DAI
            3000,
            0,
            0,
            MAX_U32
        );

        LimitOrderBook.LimitOrder memory order2 = newMockStoplossOrder(
            USDC,
            WETH,
            1,
            false,
            false,
            false,
            0,
            1,
            5000000000000000000001, //5001 DAI
            3000,
            0,
            0,
            MAX_U32
        );
        LimitOrderBook.LimitOrder memory order3 = newMockStoplossOrder(
            DAI,
            WETH,
            1,
            false,
            true,
            false,
            0,
            1,
            5000000000000000000002, //5002 DAI
            3000,
            0,
            0,
            MAX_U32
        );
        LimitOrderBook.LimitOrder[]
            memory orderBatch = new LimitOrderBook.LimitOrder[](3);
        orderBatch[0] = order1;
        orderBatch[1] = order2;
        orderBatch[2] = order3;

        return orderBatch;
    }

    function placeNewMockTokenToWethBatchStoploss()
        internal
        returns (bytes32[] memory)
    {
        swapHelper.swapEthForTokenWithUniV2(1000 ether, UNI);
        swapHelper.swapEthForTokenWithUniV2(1000 ether, USDC);

        LimitOrderBook.LimitOrder memory order1 = newMockStoplossOrder(
            DAI,
            WETH,
            1,
            false,
            true,
            false,
            0,
            1,
            5000000000000000000000, //5000 DAI
            3000,
            0,
            0,
            MAX_U32
        );

        LimitOrderBook.LimitOrder memory order2 = newMockStoplossOrder(
            USDC,
            WETH,
            1,
            false,
            true,
            false,
            0,
            1,
            5000000000000000000001, //5001 DAI
            3000,
            0,
            0,
            MAX_U32
        );
        LimitOrderBook.LimitOrder memory order3 = newMockStoplossOrder(
            DAI,
            WETH,
            1,
            false,
            true,
            false,
            0,
            1,
            5000000000000000000002, //5002 DAI
            3000,
            0,
            0,
            MAX_U32
        );
        LimitOrderBook.LimitOrder[]
            memory orderBatch = new LimitOrderBook.LimitOrder[](3);
        orderBatch[0] = order1;
        orderBatch[1] = order2;
        orderBatch[2] = order3;
        bytes32[] memory orderIds = new bytes32[](3);
        bytes32[] memory returnIds = placeMultipleMockOrder(orderBatch);
        orderIds[0] = returnIds[0];
        orderIds[1] = returnIds[1];
        orderIds[2] = returnIds[2];

        return orderIds;
    }

    function newMockTokenToWethBatch_IncongruentTokenIn()
        internal
        returns (LimitOrderBook.LimitOrder[] memory)
    {
        swapHelper.swapEthForTokenWithUniV2(1000 ether, UNI);
        swapHelper.swapEthForTokenWithUniV2(1000 ether, USDC);

        LimitOrderBook.LimitOrder memory order1 = newMockOrder(
            DAI,
            WETH,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000000, //5000 DAI
            3000,
            0,
            0,
            MAX_U32
        );

        LimitOrderBook.LimitOrder memory order2 = newMockOrder(
            USDC,
            WETH,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000001, //5001 DAI
            3000,
            0,
            0,
            MAX_U32
        );
        LimitOrderBook.LimitOrder memory order3 = newMockOrder(
            DAI,
            WETH,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000002, //5002 DAI
            3000,
            0,
            0,
            MAX_U32
        );

        LimitOrderBook.LimitOrder[]
            memory orderBatch = new LimitOrderBook.LimitOrder[](3);
        orderBatch[0] = order1;
        orderBatch[1] = order2;
        orderBatch[2] = order3;

        return orderBatch;
    }

    function placeNewMockTokenToWethBatch_IncongruentTaxedTokenInBatch()
        internal
        returns (bytes32[] memory)
    {
        swapHelper.swapEthForTokenWithUniV2(1000 ether, DAI);

        LimitOrderBook.LimitOrder memory order1 = newMockOrder(
            DAI,
            WETH,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000000, //5000 DAI
            3000,
            0,
            0,
            MAX_U32
        );

        LimitOrderBook.LimitOrder memory order2 = newMockOrder(
            DAI,
            WETH,
            1,
            false,
            true,
            0,
            1,
            5000000000000000000001, //5001 DAI
            3000,
            0,
            0,
            MAX_U32
        );
        LimitOrderBook.LimitOrder memory order3 = newMockOrder(
            DAI,
            WETH,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000002, //5002 DAI
            3000,
            0,
            0,
            MAX_U32
        );

        LimitOrderBook.LimitOrder[]
            memory orderBatch = new LimitOrderBook.LimitOrder[](3);
        orderBatch[0] = order1;
        orderBatch[1] = order2;
        orderBatch[2] = order3;

        return placeMultipleMockOrder(orderBatch);
    }

    function newMockTokenToWethBatch_IncongruentTaxedTokenInBatch()
        internal
        returns (LimitOrderBook.LimitOrder[] memory)
    {
        swapHelper.swapEthForTokenWithUniV2(1000 ether, DAI);

        LimitOrderBook.LimitOrder memory order1 = newMockOrder(
            DAI,
            WETH,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000000, //5000 DAI
            3000,
            0,
            0,
            MAX_U32
        );

        LimitOrderBook.LimitOrder memory order2 = newMockOrder(
            DAI,
            WETH,
            1,
            false,
            true,
            0,
            1,
            5000000000000000000001, //5001 DAI
            3000,
            0,
            0,
            MAX_U32
        );
        LimitOrderBook.LimitOrder memory order3 = newMockOrder(
            DAI,
            WETH,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000002, //5002 DAI
            3000,
            0,
            0,
            MAX_U32
        );

        LimitOrderBook.LimitOrder[]
            memory orderBatch = new LimitOrderBook.LimitOrder[](3);
        orderBatch[0] = order1;
        orderBatch[1] = order2;
        orderBatch[2] = order3;

        return orderBatch;
    }

    function placeNewMockTokenToWethBatch_IncongruentTokenOut()
        internal
        returns (bytes32[] memory)
    {
        swapHelper.swapEthForTokenWithUniV2(1000 ether, DAI);

        LimitOrderBook.LimitOrder memory order1 = newMockOrder(
            DAI,
            WETH,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000000, //5000 DAI
            3000,
            0,
            0,
            MAX_U32
        );

        LimitOrderBook.LimitOrder memory order2 = newMockOrder(
            DAI,
            USDC,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000001, //5001 DAI
            3000,
            0,
            0,
            MAX_U32
        );
        LimitOrderBook.LimitOrder memory order3 = newMockOrder(
            DAI,
            WETH,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000002, //5002 DAI
            3000,
            0,
            0,
            MAX_U32
        );

        LimitOrderBook.LimitOrder[]
            memory orderBatch = new LimitOrderBook.LimitOrder[](3);
        orderBatch[0] = order1;
        orderBatch[1] = order2;
        orderBatch[2] = order3;

        return placeMultipleMockOrder(orderBatch);
    }

    function newMockTokenToWethBatch_IncongruentTokenOut()
        internal
        returns (LimitOrderBook.LimitOrder[] memory)
    {
        swapHelper.swapEthForTokenWithUniV2(1000 ether, DAI);

        LimitOrderBook.LimitOrder memory order1 = newMockOrder(
            DAI,
            WETH,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000000, //5000 DAI
            3000,
            0,
            0,
            MAX_U32
        );

        LimitOrderBook.LimitOrder memory order2 = newMockOrder(
            DAI,
            USDC,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000001, //5001 DAI
            3000,
            0,
            0,
            MAX_U32
        );
        LimitOrderBook.LimitOrder memory order3 = newMockOrder(
            DAI,
            WETH,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000002, //5002 DAI
            3000,
            0,
            0,
            MAX_U32
        );

        LimitOrderBook.LimitOrder[]
            memory orderBatch = new LimitOrderBook.LimitOrder[](3);
        orderBatch[0] = order1;
        orderBatch[1] = order2;
        orderBatch[2] = order3;

        return orderBatch;
    }

    function newMockTokenToWethBatch_IncongruentFeeIn()
        internal
        returns (LimitOrderBook.LimitOrder[] memory)
    {
        swapHelper.swapEthForTokenWithUniV2(1000 ether, DAI);

        LimitOrderBook.LimitOrder memory order1 = newMockOrder(
            DAI,
            WETH,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000000, //5000 DAI
            3000,
            300,
            0,
            MAX_U32
        );

        LimitOrderBook.LimitOrder memory order2 = newMockOrder(
            DAI,
            USDC,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000001, //5001 DAI
            3000,
            0,
            0,
            MAX_U32
        );

        LimitOrderBook.LimitOrder[]
            memory orderBatch = new LimitOrderBook.LimitOrder[](2);
        orderBatch[0] = order1;
        orderBatch[1] = order2;

        return orderBatch;
    }

    function newMockTokenToWethBatch_IncongruentFeeOut()
        internal
        returns (LimitOrderBook.LimitOrder[] memory)
    {
        swapHelper.swapEthForTokenWithUniV2(1000 ether, DAI);

        LimitOrderBook.LimitOrder memory order1 = newMockOrder(
            DAI,
            WETH,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000000, //5000 DAI
            3000,
            300,
            300,
            MAX_U32
        );

        LimitOrderBook.LimitOrder memory order2 = newMockOrder(
            DAI,
            USDC,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000001, //5001 DAI
            3000,
            300,
            500,
            MAX_U32
        );

        LimitOrderBook.LimitOrder[]
            memory orderBatch = new LimitOrderBook.LimitOrder[](2);
        orderBatch[0] = order1;
        orderBatch[1] = order2;

        return orderBatch;
    }

    function placeNewMockTokenToWethBatch_IncongruentBuySellStatus()
        internal
        returns (bytes32[] memory)
    {
        swapHelper.swapEthForTokenWithUniV2(1000 ether, DAI);

        LimitOrderBook.LimitOrder memory order1 = newMockOrder(
            DAI,
            WETH,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000000, //5000 DAI
            3000,
            0,
            0,
            MAX_U32
        );

        LimitOrderBook.LimitOrder memory order2 = newMockOrder(
            DAI,
            WETH,
            1,
            true,
            false,
            0,
            1,
            5000000000000000000001, //5001 DAI
            3000,
            0,
            0,
            MAX_U32
        );
        LimitOrderBook.LimitOrder memory order3 = newMockOrder(
            DAI,
            WETH,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000002, //5002 DAI
            3000,
            0,
            0,
            MAX_U32
        );

        LimitOrderBook.LimitOrder[]
            memory orderBatch = new LimitOrderBook.LimitOrder[](3);
        orderBatch[0] = order1;
        orderBatch[1] = order2;
        orderBatch[2] = order3;

        return placeMultipleMockOrder(orderBatch);
    }

    function newMockTokenToWethBatch_IncongruentBuySellStatus()
        internal
        returns (LimitOrderBook.LimitOrder[] memory)
    {
        swapHelper.swapEthForTokenWithUniV2(1000 ether, DAI);
        LimitOrderBook.LimitOrder memory order1 = newMockOrder(
            DAI,
            WETH,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000000, //5000 DAI
            3000,
            0,
            0,
            MAX_U32
        );

        LimitOrderBook.LimitOrder memory order2 = newMockOrder(
            DAI,
            WETH,
            1,
            true,
            false,
            0,
            1,
            5000000000000000000001, //5001 DAI
            3000,
            0,
            0,
            MAX_U32
        );
        LimitOrderBook.LimitOrder memory order3 = newMockOrder(
            DAI,
            WETH,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000002, //5002 DAI
            3000,
            0,
            0,
            MAX_U32
        );

        LimitOrderBook.LimitOrder[]
            memory orderBatch = new LimitOrderBook.LimitOrder[](3);
        orderBatch[0] = order1;
        orderBatch[1] = order2;
        orderBatch[2] = order3;

        return orderBatch;
    }

    function placeNewMockWethToTokenBatch()
        internal
        returns (bytes32[] memory)
    {
        LimitOrderBook.LimitOrder memory order1 = newMockOrder(
            WETH,
            DAI,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000000, //5000 WETH
            3000,
            0,
            0,
            MAX_U32
        );

        LimitOrderBook.LimitOrder memory order2 = newMockOrder(
            WETH,
            DAI,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000000, //5000 WETH
            3000,
            0,
            0,
            MAX_U32
        );
        LimitOrderBook.LimitOrder memory order3 = newMockOrder(
            WETH,
            DAI,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000000, //5000 WETH
            3000,
            0,
            0,
            MAX_U32
        );
        LimitOrderBook.LimitOrder memory order4 = newMockOrder(
            WETH,
            DAI,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000000, //5000 WETH
            3000,
            0,
            0,
            MAX_U32
        );
        LimitOrderBook.LimitOrder memory order5 = newMockOrder(
            WETH,
            DAI,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000000, //5000 WETH
            3000,
            0,
            0,
            MAX_U32
        );
        LimitOrderBook.LimitOrder memory order6 = newMockOrder(
            WETH,
            DAI,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000000, //5000 WETH
            3000,
            0,
            0,
            MAX_U32
        );

        LimitOrderBook.LimitOrder[]
            memory orderBatch = new LimitOrderBook.LimitOrder[](6);
        orderBatch[0] = order1;
        orderBatch[1] = order2;
        orderBatch[2] = order3;
        orderBatch[3] = order4;
        orderBatch[4] = order5;
        orderBatch[5] = order6;
        return placeMultipleMockOrder(orderBatch);
    }

    function placeNewMockWethToTaxedBatch()
        internal
        returns (bytes32[] memory)
    {
        LimitOrderBook.LimitOrder memory order = newMockOrder(
            WETH,
            TAXED_TOKEN,
            1,
            false,
            true,
            0,
            1,
            20000000000000000, //2,000,000
            3000,
            0,
            0,
            MAX_U32
        );

        LimitOrderBook.LimitOrder memory order1 = newMockOrder(
            WETH,
            TAXED_TOKEN,
            1,
            false,
            true,
            0,
            1,
            20000000000000001, //2,000,001
            3000,
            0,
            0,
            MAX_U32
        );
        LimitOrderBook.LimitOrder memory order2 = newMockOrder(
            WETH,
            TAXED_TOKEN,
            1,
            false,
            true,
            0,
            1,
            20000000000000002, //2,000,002
            3000,
            0,
            0,
            MAX_U32
        );

        LimitOrderBook.LimitOrder[]
            memory orderBatch = new LimitOrderBook.LimitOrder[](3);
        orderBatch[0] = order;
        orderBatch[1] = order1;
        orderBatch[2] = order2;

        return placeMultipleMockOrder(orderBatch);
    }

    function placeNewMockTokenToTokenBatch()
        internal
        returns (bytes32[] memory)
    {
        swapHelper.swapEthForTokenWithUniV2(10000 ether, USDC);

        LimitOrderBook.LimitOrder memory order1 = newMockOrder(
            USDC,
            UNI,
            1,
            false,
            false,
            0,
            1,
            5000000000, //5000 USDC
            3000,
            3000,
            0,
            MAX_U32
        );

        LimitOrderBook.LimitOrder memory order2 = newMockOrder(
            USDC,
            UNI,
            1,
            false,
            false,
            0,
            1,
            5000000000, //5000 USDC
            3000,
            3000,
            0,
            MAX_U32
        );

        // LimitOrderBook.LimitOrder memory order3 = newMockOrder(
        //     USDC,
        //     UNI,
        //     1,
        //     false,
        //     false,
        //     0,
        //     1,
        //     5000000000, //5000 USDC
        //     3000,
        //     3000,
        //     0,
        //     MAX_U32
        // );

        // LimitOrderBook.LimitOrder memory order4 = newMockOrder(
        //     USDC,
        //     UNI,
        //     1,
        //     false,
        //     false,
        //     0,
        //     1,
        //     5000000000, //5000 USDC
        //     3000,
        //     3000,
        //     0,
        //     MAX_U32
        // );

        // LimitOrderBook.LimitOrder memory order5 = newMockOrder(
        //     USDC,
        //     UNI,
        //     1,
        //     false,
        //     false,
        //     0,
        //     1,
        //     5000000000, //5000 DAI
        //     3000,
        //     3000,
        //     0,
        //     MAX_U32
        // );

        // LimitOrderBook.LimitOrder memory order6 = newMockOrder(
        //     USDC,
        //     UNI,
        //     1,
        //     false,
        //     false,
        //     0,
        //     1,
        //     5000000000, //5000 DAI
        //     3000,
        //     3000,
        //     0,
        //     MAX_U32
        // );

        LimitOrderBook.LimitOrder[]
            memory orderBatch = new LimitOrderBook.LimitOrder[](2);
        orderBatch[0] = order1;
        orderBatch[1] = order2;
        // orderBatch[2] = order3;
        // orderBatch[3] = order4;
        // orderBatch[4] = order5;
        // orderBatch[5] = order6;

        return placeMultipleMockOrder(orderBatch);
    }

    function placeNewMockTokenToTokenStoplossBatch()
        internal
        returns (bytes32[] memory)
    {
        swapHelper.swapEthForTokenWithUniV2(10000 ether, USDC);

        LimitOrderBook.LimitOrder memory order1 = newMockStoplossOrder(
            USDC,
            UNI,
            1,
            false,
            true,
            false,
            0,
            1,
            5000000000, //5000 USDC
            3000,
            3000,
            0,
            MAX_U32
        );

        LimitOrderBook.LimitOrder memory order2 = newMockStoplossOrder(
            USDC,
            UNI,
            1,
            false,
            true,
            false,
            0,
            1,
            5000000000, //5000 USDC
            3000,
            3000,
            0,
            MAX_U32
        );

        LimitOrderBook.LimitOrder[]
            memory orderBatch = new LimitOrderBook.LimitOrder[](2);
        orderBatch[0] = order1;
        orderBatch[1] = order2;

        return placeMultipleMockOrder(orderBatch);
    }

    function placeNewMockTokenToTokenBatchDuplicateOrderIds()
        internal
        returns (bytes32[] memory)
    {
        swapHelper.swapEthForTokenWithUniV2(10000 ether, USDC);

        LimitOrderBook.LimitOrder memory order1 = newMockOrder(
            USDC,
            UNI,
            1,
            false,
            false,
            0,
            1,
            5000000000, //5000 USDC
            3000,
            3000,
            0,
            MAX_U32
        );

        LimitOrderBook.LimitOrder memory order2 = newMockOrder(
            USDC,
            UNI,
            1,
            false,
            false,
            0,
            1,
            5000000000, //5000 USDC
            3000,
            3000,
            0,
            MAX_U32
        );

        LimitOrderBook.LimitOrder[]
            memory orderBatch = new LimitOrderBook.LimitOrder[](2);
        orderBatch[0] = order1;
        orderBatch[1] = order2;

        bytes32[] memory returnIds = placeMultipleMockOrder(orderBatch);
        bytes32[] memory duplicateIdArray = new bytes32[](3);
        duplicateIdArray[0] = returnIds[0];
        duplicateIdArray[1] = returnIds[1];
        duplicateIdArray[2] = returnIds[1]; //Duplicate id in batch should cause revert
        return duplicateIdArray;
    }

    function placeNewMockTaxedToTokenBatch()
        internal
        returns (bytes32[] memory)
    {
        LimitOrderBook.LimitOrder memory order = newMockOrder(
            TAXED_TOKEN,
            DAI,
            1,
            false,
            true,
            9000,
            1,
            2000000000000000000000, //2,000,000
            3000,
            3000,
            0,
            MAX_U32
        );

        LimitOrderBook.LimitOrder memory order1 = newMockOrder(
            TAXED_TOKEN,
            DAI,
            1,
            false,
            true,
            9000,
            1,
            2000000000000000000000, //2,000,001
            3000,
            3000,
            0,
            MAX_U32
        );

        //    LimitOrderBook.LimitOrder memory order2 = newMockOrder(
        //         TAXED_TOKEN_3,
        //         DAI,
        //         1,
        //         false,
        //         true,
        //         9000,
        //         1,
        //         2000000000000000000000000, //2,000,002
        //         3000,
        //         3000,
        //         0,
        //         MAX_U32
        //     );

        LimitOrderBook.LimitOrder[]
            memory orderBatch = new LimitOrderBook.LimitOrder[](2);
        orderBatch[0] = order;
        orderBatch[1] = order1;
        // orderBatch[2] = order2;

        return placeMultipleMockOrder(orderBatch);
    }

    function placeNewMockTaxedToTaxedTokenBatch()
        internal
        returns (bytes32[] memory)
    {
        LimitOrderBook.LimitOrder memory order = newMockOrder(
            TAXED_TOKEN,
            TAXED_TOKEN_1,
            1,
            false,
            true,
            9000,
            1,
            2000000000000000000000, //2,000,000
            3000,
            3000,
            0,
            MAX_U32
        );

        LimitOrderBook.LimitOrder[]
            memory orderBatch = new LimitOrderBook.LimitOrder[](1);
        orderBatch[0] = order;

        return placeMultipleMockOrder(orderBatch);
    }

    function newMockTokenToTokenBatch()
        internal
        returns (LimitOrderBook.LimitOrder[] memory)
    {
        swapHelper.swapEthForTokenWithUniV2(1000 ether, DAI);

        LimitOrderBook.LimitOrder memory order1 = newMockOrder(
            DAI,
            UNI,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000000, //5000 DAI
            3000,
            3000,
            0,
            MAX_U32
        );

        LimitOrderBook.LimitOrder memory order2 = newMockOrder(
            DAI,
            UNI,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000000, //5000 DAI
            3000,
            3000,
            0,
            MAX_U32
        );

        LimitOrderBook.LimitOrder memory order3 = newMockOrder(
            DAI,
            UNI,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000000, //5000 DAI
            3000,
            3000,
            0,
            MAX_U32
        );

        LimitOrderBook.LimitOrder[]
            memory orderBatch = new LimitOrderBook.LimitOrder[](3);
        orderBatch[0] = order1;
        orderBatch[1] = order2;
        orderBatch[2] = order3;

        return orderBatch;
    }

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
        uint256 _minExecutionCredit
    )
        ConveyorExecutor(
            _weth,
            _usdc,
            _limitOrderQuoter,
            _initBytecodes,
            _dexFactories,
            _isUniV2,
            _minExecutionCredit
        )
    {}

    function getV3PoolFee(address pairAddress)
        public
        view
        returns (uint24 poolFee)
    {
        return getV3PoolFee(pairAddress);
    }

    function lpIsNotUniV3(address lp) public returns (bool) {
        return _lpIsNotUniV3(lp);
    }

    // receive() external payable {}

    function swapV2(
        address _tokenIn,
        address _tokenOut,
        address _lp,
        uint256 _amountIn,
        uint256 _amountOutMin,
        address _receiver,
        address _sender
    ) public returns (uint256) {
        return
            _swapV2(
                _tokenIn,
                _tokenOut,
                _lp,
                _amountIn,
                _amountOutMin,
                _receiver,
                _sender
            );
    }

    function swapV3(
        address _lp,
        address _tokenIn,
        address _tokenOut,
        uint24 _fee,
        uint256 _amountIn,
        uint256 _amountOutMin,
        address _receiver,
        address _sender
    ) public returns (uint256) {
        return
            _swapV3(
                _lp,
                _tokenIn,
                _tokenOut,
                _fee,
                _amountIn,
                _amountOutMin,
                _receiver,
                _sender
            );
    }

    function calculateV2SpotPrice(
        address token0,
        address token1,
        address _factory,
        bytes32 _initBytecode
    ) public view returns (SpotReserve memory spRes, address poolAddress) {
        return _calculateV2SpotPrice(token0, token1, _factory, _initBytecode);
    }

    function calculateV3SpotPrice(
        address token0,
        address token1,
        uint24 FEE,
        address _factory
    ) public returns (SpotReserve memory, address) {
        return _calculateV3SpotPrice(token0, token1, FEE, _factory);
    }

    function swap(
        address _tokenIn,
        address _tokenOut,
        address _lp,
        uint24 _fee,
        uint256 _amountIn,
        uint256 _amountOutMin,
        address _receiver,
        address _sender
    ) public returns (uint256 amountReceived) {
        return
            _swap(
                _tokenIn,
                _tokenOut,
                _lp,
                _fee,
                _amountIn,
                _amountOutMin,
                _receiver,
                _sender
            );
    }
}

contract LimitOrderRouterWrapper is LimitOrderRouter {
    constructor(
        address _weth,
        address _usdc,
        address _limitOrderExecutor,
        uint256 _minExecutionCredits
    )
        LimitOrderRouter(
            _weth,
            _usdc,
            _limitOrderExecutor,
            _minExecutionCredits
        )
    {}

    function invokeOnlyEOA() public onlyEOA {}

    function validateOrderSequencing(LimitOrder[] memory orders) public pure {
        _validateOrderSequencing(orders);
    }
}
