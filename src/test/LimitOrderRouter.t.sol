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

    function warp(uint256) external;
}

contract LimitOrderRouterTest is DSTest {
    //Initialize limit-v0 contract for testing
    LimitOrderRouterWrapper limitOrderRouterWrapper;
    ILimitOrderRouter limitOrderRouter;
    ILimitOrderBook orderBook;
    ConveyorExecutor limitOrderExecutor;
    LimitOrderQuoter limitOrderQuoter;

    ScriptRunner scriptRunner;

    Swap swapHelper;
    Swap swapHelperUniV2;
    uint256 REFRESH_FEE = 20000000000000000;
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

        limitOrderExecutor = new ConveyorExecutor(
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

        orderBook = ILimitOrderBook(limitOrderExecutor.LIMIT_ORDER_ROUTER());

        //Wrapper contract to test internal functions
        limitOrderRouterWrapper = new LimitOrderRouterWrapper(
            0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
            0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48,
            address(limitOrderExecutor),
            1
        );
    }

    function testOnlyEOA() public {
        cheatCodes.prank(tx.origin);
        limitOrderRouterWrapper.invokeOnlyEOA();
    }

    function testFailOnlyEOA() public {
        limitOrderRouterWrapper.invokeOnlyEOA();
    }

    //================================================================
    //================= Validate Order Sequence Tests ================
    //================================================================

    function testValidateOrderSequence() public {
        cheatCodes.deal(address(swapHelper), MAX_UINT);

        LimitOrderBook.LimitOrder[]
            memory orderBatch = newMockTokenToTokenBatch();

        limitOrderRouterWrapper.validateOrderSequencing(orderBatch);
    }

    function testFailValidateOrderSequence_InvalidBatchOrder() public {
        cheatCodes.deal(address(swapHelper), MAX_UINT);

        LimitOrderBook.LimitOrder[]
            memory orderBatch = newMockTokenToWethBatch_InvalidBatchOrdering();

        limitOrderRouterWrapper.validateOrderSequencing(orderBatch);
    }

    function testFailValidateOrderSequence_IncongruentInputTokenInBatch()
        public
    {
        cheatCodes.deal(address(swapHelper), MAX_UINT);

        LimitOrderBook.LimitOrder[]
            memory orderBatch = newMockTokenToWethBatch_IncongruentTokenIn();

        limitOrderRouterWrapper.validateOrderSequencing(orderBatch);
    }

    function testFailValidateOrderSequence_IncongruentStoplossStatus() public {
        cheatCodes.deal(address(swapHelper), MAX_UINT);

        LimitOrderBook.LimitOrder[]
            memory orderBatch = placeNewMockTokenToWethBatch_IncongruentStoploss();

        limitOrderRouterWrapper.validateOrderSequencing(orderBatch);
    }

    function testFailValidateOrderSequence_IncongruentTokenOut() public {
        cheatCodes.deal(address(swapHelper), MAX_UINT);

        LimitOrderBook.LimitOrder[]
            memory orderBatch = newMockTokenToWethBatch_IncongruentTokenOut();
        limitOrderRouterWrapper.validateOrderSequencing(orderBatch);
    }

    function testFailValidateOrderSequence_IncongruentFeeIn() public {
        cheatCodes.deal(address(swapHelper), MAX_UINT);

        LimitOrderBook.LimitOrder[]
            memory orderBatch = newMockTokenToWethBatch_IncongruentFeeIn();
        limitOrderRouterWrapper.validateOrderSequencing(orderBatch);
    }

    function testFailValidateOrderSequence_IncongruentFeeOut() public {
        cheatCodes.deal(address(swapHelper), MAX_UINT);

        LimitOrderBook.LimitOrder[]
            memory orderBatch = newMockTokenToWethBatch_IncongruentFeeOut();
        limitOrderRouterWrapper.validateOrderSequencing(orderBatch);
    }

    function testFailValidateOrderSequence_IncongruentBuySellStatusInBatch()
        public
    {
        cheatCodes.deal(address(swapHelper), MAX_UINT);

        LimitOrderBook.LimitOrder[]
            memory orderBatch = newMockTokenToWethBatch_IncongruentBuySellStatus();
        limitOrderRouterWrapper.validateOrderSequencing(orderBatch);
    }

    function testFailValidateOrderSequence_IncongruentTaxedTokenInBatch()
        public
    {
        cheatCodes.deal(address(swapHelper), MAX_UINT);

        LimitOrderBook.LimitOrder[]
            memory orderBatch = newMockTokenToWethBatch_IncongruentTaxedTokenInBatch();
        limitOrderRouterWrapper.validateOrderSequencing(orderBatch);
    }

    function testValidateAndCancelOrder() public {
        cheatCodes.prank(address(this));
        limitOrderExecutor.checkIn();
        LimitOrderBook.LimitOrder memory order = newOrder(
            WETH,
            USDC,
            0,
            1 ether,
            0
        );

        cheatCodes.deal(address(this), 1 ether);

        IERC20(WETH).approve(address(limitOrderExecutor), MAX_UINT);

        (bool depositSuccess, ) = address(WETH).call{value: 1 ether}(
            abi.encodeWithSignature("deposit()")
        );
        require(depositSuccess, "failure when depositing ether into weth");

        bytes32 orderId = placeMockOrder(order);

        IWETH(WETH).withdraw(100000);

        bool canceled = limitOrderRouter.validateAndCancelOrder(orderId);
        assertTrue(canceled);

        LimitOrderBook.OrderType orderType = orderBook.addressToOrderIds(
            address(this),
            orderId
        );

        assert(orderType == LimitOrderBook.OrderType.CanceledLimitOrder);
    }

    //Should fail validateAndCancel since user has the min credit balance
    function testFailValidateAndCancelOrder() public {
        cheatCodes.prank(address(this));
        limitOrderExecutor.checkIn();
        LimitOrderBook.LimitOrder memory order = newOrder(
            WETH,
            USDC,
            0,
            1 ether,
            0
        );

        cheatCodes.deal(address(this), 1 ether);

        (bool depositSuccess, ) = address(WETH).call{value: 1 ether}(
            abi.encodeWithSignature("deposit()")
        );
        require(depositSuccess, "failure when depositing ether into weth");

        bytes32 orderId = placeMockOrder(order);

        bool canceled = limitOrderRouter.validateAndCancelOrder(orderId);
        assertTrue(!canceled);

        LimitOrderBook.OrderType orderType = orderBook.addressToOrderIds(
            address(this),
            orderId
        );
        assert(orderType == LimitOrderBook.OrderType.PendingLimitOrder);
    }

    ///@notice Refresh order test
    function testRefreshOrder() public {
        cheatCodes.deal(address(swapHelper), MAX_UINT);
        swapHelper.swapEthForTokenWithUniV2(1000 ether, DAI);
        IERC20(DAI).approve(address(limitOrderExecutor), MAX_UINT);
        //Initialize a new order
        LimitOrderBook.LimitOrder memory order = newMockOrder(
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

        bytes32 orderId = placeMockOrder(order);

        bytes32[] memory orderBatch = new bytes32[](1);

        orderBatch[0] = orderId;
        uint256 executionCreditBefore;
        ///Ensure the order has been placed
        for (uint256 i = 0; i < orderBatch.length; ++i) {
            LimitOrderBook.LimitOrder memory order0 = orderBook
                .getLimitOrderById(orderBatch[i]);
            executionCreditBefore += order0.executionCredit;
            assert(order0.orderId != bytes32(0));
        }

        cheatCodes.warp(block.timestamp + 2592000);
        cheatCodes.prank(address(this));
        limitOrderExecutor.checkIn();
        limitOrderRouter.refreshOrder(orderBatch);

        //Ensure the order was not canceled and lastRefresh timestamp is updated to block.timestamp
        for (uint256 i = 0; i < orderBatch.length; ++i) {
            LimitOrderBook.LimitOrder memory order0 = orderBook
                .getLimitOrderById(orderBatch[i]);
            assert(
                order0.executionCredit == executionCreditBefore - REFRESH_FEE
            );
            assert(order0.lastRefreshTimestamp == block.timestamp);
        }
    }

    ///Test refresh order, cancel order since order has expired test
    function testRefreshOrder_CancelOrderOrderExpired() public {
        cheatCodes.prank(address(this));
        limitOrderExecutor.checkIn();
        cheatCodes.deal(address(swapHelper), MAX_UINT);
        swapHelper.swapEthForTokenWithUniV2(1000 ether, DAI);
        IERC20(DAI).approve(address(limitOrderExecutor), MAX_UINT);

        //Initialize a new order
        LimitOrderBook.LimitOrder memory order = newMockOrder(
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
            0
        );

        bytes32 orderId = placeMockOrder(order);

        bytes32[] memory orderBatch = new bytes32[](1);

        orderBatch[0] = orderId;

        //Ensure order was not canceled
        for (uint256 i = 0; i < orderBatch.length; ++i) {
            LimitOrderBook.LimitOrder memory order0 = orderBook
                .getLimitOrderById(orderBatch[i]);

            assert(order0.orderId != bytes32(0));
        }

        limitOrderRouter.refreshOrder(orderBatch);

        //Ensure the orders are canceled
        for (uint256 i = 0; i < orderBatch.length; ++i) {
            LimitOrderBook.OrderType orderType = orderBook.addressToOrderIds(
                address(this),
                orderBatch[i]
            );
            assert(orderType == LimitOrderBook.OrderType.CanceledLimitOrder);
        }
    }

    //block 15233771
    ///Test refresh order, Order not refreshable since last refresh timestamp isn't beyond the refresh threshold from the current block.timestamp
    function testFailRefreshOrder_OrderNotEligibleForRefresh() public {
        cheatCodes.prank(address(this));
        limitOrderExecutor.checkIn();
        cheatCodes.deal(address(swapHelper), MAX_UINT);
        swapHelper.swapEthForTokenWithUniV2(1000 ether, DAI);
        IERC20(DAI).approve(address(limitOrderExecutor), MAX_UINT);

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
            1659049037,
            MAX_U32
        );

        bytes32 orderId = placeMockOrder(order1);

        bytes32[] memory orderBatch = new bytes32[](1);

        orderBatch[0] = orderId;
        for (uint256 i = 0; i < orderBatch.length; ++i) {
            LimitOrderBook.LimitOrder memory order0 = orderBook
                .getLimitOrderById(orderBatch[i]);

            assert(order0.orderId != bytes32(0));
        }

        limitOrderRouter.refreshOrder(orderBatch);
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
            taxIn: taxIn,
            price: price,
            executionCredit: 0,
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

contract LimitOrderRouterWrapper is LimitOrderRouter {
    LimitOrderRouter limitorderRouter;

    constructor(
        address _weth,
        address _usdc,
        address _limitOrderExecutor,
        uint256 _minExecutionCredit
    )
        LimitOrderRouter(_weth, _usdc, _limitOrderExecutor, _minExecutionCredit)
    {}

    function invokeOnlyEOA() public onlyEOA {}

    function validateOrderSequencing(LimitOrder[] memory orders) public pure {
        _validateOrderSequencing(orders);
    }
}
