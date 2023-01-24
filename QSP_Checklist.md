# Updated Scope
- `src/ConveyorExecutor.sol`
- `src/LimitOrderSwapRouter.sol`
- `src/LimitOrderRouter.sol`
- `src/LimitOrderBook.sol`
- `src/SandboxLimitOrderRouter.sol`
- `src/SandboxLimitOrderBook.sol`
- `src/LimitOrderQuoter.sol`
- `src/ConveyorGasOracle.sol`
- `src/ConveyorSwapAggregator.sol`
- `src/ConveyorErrors.sol`
- `src/interfaces/IConveyorExecutor.sol`
- `src/interfaces/IConveyorGasOracle.sol`
- `src/interfaces/IConveyorSwapAggregator.sol`
- `src/interfaces/ILimitOrderBook.sol`
- `src/interfaces/ILimitOrderQuoter.sol`
- `src/interfaces/ILimitOrderRouter.sol`
- `src/interfaces/ILimitOrderSwapRouter.sol`
- `src/interfaces/ISandboxLimitOrderBook.sol`
- `src/interfaces/ISandboxLimitOrderRouter.sol`
- `src/lib/ConveyorTickMath.sol`
- `src/lib/ConveyorMath.sol`
- `src/lib/ConveyorFeeMath.sol`
  
# Architectural Changes
The protocol has been split into two seperate LimitOrder systems, `LimitOrders` and `SandboxLimitOrders`. 

The `LimitOrder` system is the old contract architecture with a few small modifications/optimizations. The `LimitOrder` system was changed to have a linear execution flow, and will be exclusively used for `stoploss` orders although it is capable of executing any type of limit order.

In addition to the previoius `LimitOrder` system, we created the `SandboxLimitOrders` system to reduce execution cost, and significantly increase the flexibility of the protocol. To save execution cost and allow for maximum flexiblity in execution, the `SandboxLimitOrder` system optimistically executes arbitrary calldata passed by the executor and simply validates the users token balances pre/post execution to ensure order fulfillment, allowing for significant gas savings for the user. 

## LimitOrder System
The following contracts are part of the LimitOrder system.

`LimitOrderBook.sol`, Previously `OrderBook.sol` </br>
`LimitOrderRouter.sol` </br>
`LimitOrderQuoter.sol`, Previously `LimitOrderBatcher.sol` </br>
`lib/ConveyorTickMath.sol`, Replaces V3 Quoter Logic for V3 price simulation + Q96.64-> X128 Conversion logic </br>
`lib/ConveyorFeeMath` </br>
`SwapRouter` </br>
`ConveyorExecutor`, Previously `LimitOrderExecutor`</br>
`ConveyorGasOracle`, Previously `GasOracle`

## SandboxLimitOrder System
The following contracts are part of the SandboxLimitOrder system.

`SandboxLimitOrderBook.sol`, Previously `OrderBook.sol` </br>
`SandboxLimitOrderRouter.sol` </br>
`ConveyorGasOracle`, Previously `GasOracle`



## Uniswap V3 Changes
#### Function `LimitOrderBatcher.calculateAmountOutMinAToWeth()`
We eliminated the use of the v3 Quoter in the contract. Our quoting logic was modeled after: (https://github.com/Uniswap/v3-core/blob/main/contracts/UniswapV3Pool.sol#L596).

The implementation is located in `src/lib/ConveyorTickMath.sol` within the function `simulateAmountOutOnSqrtPriceX96`. 
This function is called in `src/LimitOrderQuoter.sol` within `calculateAmountOutMinAToWeth` </br>

Tests:<br />
Reference `src/test/LimitOrderQuoter.t.sol` for `calculateAmountOutMinAToWeth` tests.<br />
Reference `src/test/ConveyorTickMath.t.sol` for `simulateAmountOutOnSqrtPriceX96` tests. <br />

#### Function `_calculateV3SpotPrice`
The V3 spot price calculation has been modified to be more gas efficient by simply calling `slot0()` on the pool, and converting `sqrtPriceX96` to `128.128` fixed point representation of `sqrtPriceX96**2`. 

#### Function `LimitOrderBatcher.calculateNextSqrtPriceX96`
This function was modified to be more gas efficient by eliminating all calls to the v3 quoter, and calculating the amountOut return value by simply calling `ConveyorTickMath.simulateAmountOutOnSqrtPriceX96`. 

#### Function `SwapRouter.getNextSqrtPriceV3`
This has been simplified to be more gas efficient by eliminating all calls to the quoter. <br />
Reference `SwapRouter`



## SandboxLimitOrder System / Architectural Overview
The `SandboxLimitOrders` system optimistically executes arbitrary calldata passed by the executor and validates the users token balances pre/post execution to ensure order fulfillment, allowing for significant gas savings for the user. The off-chain executor passes in a `SandboxMulticall` to the exectuion function.

```solidity

    struct SandboxMulticall {
        bytes32[][] orderIdBundles;
        uint128[] fillAmounts;
        address[] transferAddresses;
        Call[] calls;
    }

    struct Call {
        address target;
        bytes callData;
    }

```

`orderIdBundles` - Nested array of orderIds. `orderIdBundles[i]` will contain all `orderIds` with the same owner, and congruent `tokenIn or tokenOut`. The order of the orderIds must preserve congruency of tokens on all adjacent `orderIds`. I.e. the following should always hold true:
```
(orderIdBundle[i].tokenIn == orderIdBundle[i+1].tokenIn || orderIdBundle[i].tokenOut == orderIdBundle[i+1].tokenOut) && orderIdBundle[i].owner == orderIdBundle[i+1].owner

```
#### Note: The above `orderIdBundle` congruency condition is not explicitly enforced in the contract, but if orderIdBundles has the incorrect form the contract will revert during `validateSandboxExecutionAndFillOrders` as either the difference between the owner tokenIn balance pre/post execution will exceed the maximum threshold, or the difference between the owner tokenOut balance post/pre execution will not be equivalent to the `amountOutRequired` by the contract. Reference `SandboxLimitOrderBook.sol#L545-607`. </br>
</br>

`fillAmounts` - An array of quantity defined by the off-chain executor representing the amount to be transferred from each order owner on the input token. </bn>
`transferAddresses` - An array of addresses defined by the executor indicating the `receiver` address in `transferFrom(order.owner, receiver, fillAmount)`.

`calls` - An array of `Call` defining the target addresses and calldata to be optimistically executed. 

```solidity
    ///@notice Function to execute multiple OrderGroups
    ///@param sandboxMultiCall The calldata to be executed by the contract.
    function executeSandboxMulticall(SandboxMulticall calldata sandboxMultiCall)
        external
    {
        ISandboxLimitOrderBook(SANDBOX_LIMIT_ORDER_BOOK)
            .executeOrdersViaSandboxMulticall(sandboxMultiCall);
    }

    ///@notice Callback function that executes a sandbox multicall and is only accessible by the limitOrderExecutor.
    ///@param sandboxMulticall - Struct containing the SandboxMulticall data. See the SandboxMulticall struct for a description of each parameter.
    function sandboxRouterCallback(SandboxMulticall calldata sandboxMulticall)
        external
        onlyLimitOrderExecutor
    {
        ///@notice Iterate through each target in the calls, and optimistically call the calldata.
        for (uint256 i = 0; i < sandboxMulticall.calls.length; ) {
            Call memory sandBoxCall = sandboxMulticall.calls[i];
            ///@notice Call the target address on the specified calldata
            (bool success, ) = sandBoxCall.target.call(sandBoxCall.callData);

            if (!success) {
                revert SandboxCallFailed(i);
            }

            unchecked {
                ++i;
            }
        }
    }
```

    
### Execution Flow
`executeSandboxMulticall(SandboxMulticall calldata sandboxMultiCall)` calls the `SandboxLimitOrderBook` which caches the initial tokenIn/tokenOut balances of the order owners. The `SandboxLimitOrderBook` then calls the `ConveyorExecutor` to transfer the `fillAmount` specified by the executor to a specified `transferAddresses`. The `ConveyorExecutor` caches its current `WETH` balance, then calls `sandboxRouterCallback(SandboxMulticall calldata sandboxMulticall)` optimistically executing the calldata specified by the off-chain executor. Post execution the `ConveyorExecutor` asserts the protocol fee has been compensated, and the `SandboxLimitOrderBook` asserts that the difference between the post/pre execution tokenBalances match the order criterion and cleans up/updates all Orders state. 

### `SandboxLimitOrderBook` - Nearly identical to `OrderBook` for Order placement, cancellation refresh, and removal. 

```solidity
    struct SandboxLimitOrder {
        bool buy;
        uint32 lastRefreshTimestamp;
        uint32 expirationTimestamp;
        uint32 fillPercent;
        uint128 feeRemaining;
        uint128 amountInRemaining;
        uint128 amountOutRemaining;
        address owner;
        address tokenIn;
        address tokenOut;
        bytes32 orderId;
    }
    
    struct PreSandboxExecutionState {
        SandboxLimitOrder[] sandboxLimitOrders;
        address[] orderOwners;
        uint256[] initialTokenInBalances;
        uint256[] initialTokenOutBalances;
    }

```

`SandboxLimitOrderBook` - Details 
<ol>
    <li><code>buy</code> - Indicates whether the Order is a buy/sell limit order.</li>
    <li><code>lastRefreshTimestamp</code> - Unix Timestamp of last Order refresh</li>
    <li><code>expirationTimestamp</code> - Unix Timestamp Order expiration</li>
        <li><code>fillPercent</code> - The percentage of the initial order quantity that has been filled i.e. amountCurrentlyFilled/totalOrderQuantity</li>
        <li><code>feeRemaining</code> - The current protocol fee on the Order. The feeRemaining is initially set at Order Placement, and is a dynamic value in the case of partial fills. If <code>fillAmount</code> is filled on an Order with <code>amountInRemaining</code> as the current quantity. Then <code>feeRemaining = feeRemaining- feeRemaining *(fillAmount/amountInRemaining)</code> </li>
        <li><code>amountInRemaining</code> - The total quantity on tokenIn to be filled. </li>
        <li><code>amountOutRemaining</code> - The total quantity in tokenOut to be received for amountInRemaining of tokenIn. This is an exact amount, not an amountOutMin. The order owner will receive exactly amountOutRemaining of tokenOut for amountInRemaining of tokenIn at an exact market price of <code>amountOutRemaining/amountInRemaining</code></li>
    <li><code>owner</code> - The order owner</li>
        <li><code>tokenIn</code> - The input token</li>
        <li><code>tokenOut</code> - The output token</li>
        <li><code>orderId</code> - <code>keccak256(abi.encode(orderNonce, block.timestamp)</code> Note: orderNonce is always even, and always odd in the old system.</li>
</ol>

`PreSandboxExecutionState` - Struct containing Pre execution state balances used for post execution validation
<ol>
    <li><code>sandboxLimitOrders</code> - The Array of Orders determined by <code>Multicall.orderIdBundles</code></li>
    <li><code>orderOwners</code> - Array of owner addresses indexed congruently to <code>sandboxLimitOrders</code></li>
    <li><code>initialTokenInBalances</code> - The initial tokenIn balance of each owner prior to execution indexed respective to the former.</li>
        <li><code>initialTokenOutBalances</code> -  The initial tokenIn balance of each owner prior to execution indexed respective to the former.</li>
        
</ol>

### `ConveyorExecutor.sol`
### `ConveyorGasOracle.sol`


# QSP Resolution
The following sections detail the findings from the initial QSP report and the resolutions for each issue.

## QSP-1 Stealing User and Contract Funds ✅
Severity: 🔴**High Risk**🔴
## Description
Some funds-transferring functions in the contracts are declared as public or external but without any authorization checks, allowing anyone to arbitrarily call the functions and transfer funds.

### QSP-1_1
The visibility of the `safeTransferETH()` function in several contracts is public. The visibility allows anyone to call this function to transfer the ETH on the contract to any address directly. The following is the list of affected contracts: `LimitOrderRouter.sol`, `SwapRouter.sol`, `TaxedTokenLimitOrderExecution.sol`,`TokenToTokenLimitOrderExecution.sol`, `TokenToWethLimitOrderExecution.sol`.

### Resolution
The `safeTransferETH()` function visibility was changed to internal for all contracts affected.

### QSP-1_2
In the SwapRouter contract, several `transferXXX()` functions allow anyone to call and direct transfer the funds away. The following is the list of functions: `transferTokensToContract()`, `_transferTokensOutToOwner()`, and `_transferBeaconReward()`.
 
### Resolution
All `transferXXX()` functions were updated to only be callable by the execution contract.


### QSP-1_3
The `SwapRouter.uniswapV3SwapCallback()` function does not verify that it is called from the Uniswap V3 contract, allowing anyone to steal funds by supplying fake inputs.

### Resolution

The Uniswapv3 swap callback now has verification that the caller is a Uniswapv3 pool. First, the pool address is derived by calling the Uniswapv3 Factory. Then the function checks if the msg.sender is the pool address.

```solidity 
     address poolAddress = IUniswapV3Factory(uniswapV3Factory).getPool(
            tokenIn,
            tokenOut,
            fee
        );

        if (msg.sender != poolAddress) {
            revert UnauthorizedUniswapV3CallbackCaller();
        }
```





# QSP-2 Missing Authorization for Execution Contracts ✅
## Description
Several functions are missing authorization validation and allow anyone to call the function instead of the specific callers. Specifically, the "execution" contracts are designed to be triggered by the `LimitOrderRouter` contract. However, those functions do not verify the caller. If anyone calls those functions on the "execution" contract, it will trigger the order execution without updating the order status as fulfilled.

### Resolution
Execution functions were merged into a single execution contract called `LimitOrderExecutor.sol`. Validation was added to each execution function via a modifier called `onlyLimitOrderRouter`.


```solidity
modifier onlyLimitOrderRouter() {
    if (msg.sender != LIMIT_ORDER_ROUTER) {
        revert MsgSenderIsNotLimitOrderRouter();
    }
    _;
}
```

# QSP-3 Ignoring Return Value of ERC20 Transfer Functions ✅

## Description
Several functions use ERC20's and without checking their return values. Since per the , these functions merely throw, some implementations return on error. This is very dangerous, as transfers might not have been executed while the contract code assumes they did.

### Resolution
SafeERC20 was implemented for ERC20 transfer functions.


# QSP-4 Cancelling Order Provides Compensation Twice ✅
### Description
After validating that a user does not have sufficient gas credits, the function validateAndCancelOrder() first calls _cancelOrder(), which removes the order from the
system, transfers compensation to the message sender and emits an event. After the call, the function itself sends compensation to the message sender again and emits an
event for the second time.

### Resolution
Duplicate logic was removed.

# QSP-5 Updating an Existing Order Can Be Malicious ✅
### Description

The function updateOrder() allows the order owner to change the old order's parameters. From the code, the owner is allowed to change anything except the member orderID.


### Resolution
The `updateOrder()` function was updated to take a quantity and price, which are now the only fields that are updated instead of replacing the old order. If the user wants to update any other fields, they will have to cancel the order and place a new one. The function now has the following signature:

```solidity
function updateOrder(
    bytes32 orderId, 
    uint128 price, 
    uint128 quantity) public {
   //--snip--   
  }
```


# QSP-6 Same Order Id Can Be Executed Multiple Times ✅
### Description
In the current implementation, if the input orderIds in the function executeOrders() contains duplicate orderIDs, the function will execute the same order more than once.

### Resolution
Logic was added within the `_resolveCompletedOrder()` function to check if the order exists in the orderIdToOrder mapping. Since the orderId gets cleaned up from this mapping after successful execution, if there is a duplicate orderId in the array of orderIds being executed, the orderToOrderId mapping will return 0 for the duplicated orderId, causing a reversion.

```solidity

    function _resolveCompletedOrder(bytes32 orderId) internal {
        ///@notice Grab the order currently in the state of the contract based on the orderId of the order passed.
        Order memory order = orderIdToOrder[orderId];

        ///@notice If the order has already been removed from the contract revert.
        if (order.orderId == bytes32(0)) {
            revert DuplicateOrdersInExecution();
        }
```


# QSP-7 Incorrectly Computing the Best Price ✅
### Description
The function _findBestTokenToWethExecutionPrice() initializes the bestPrice as 0 for buy orders and type(uint256).max for sell orders. For buy orders, the code
checks for each execution price whether that price is less than the current bestPrice and updates the bestPrice and bestPriceIndex accordingly. Since there is no "better" price than 0,
the function will always return the default value of bestPriceIndex, which is 0. Similarly for sell orders, the bestPrice is already the best it can be and will always return 0.

### Resolution
Changed `_findBestTokenToWethExecutionPrice()` to initialize the bestPrice as type(uint256).max for buys and 0 for sells.

# QSP-8 Reentrancy ✅
### Description
A reentrancy vulnerability is a scenario where an attacker can repeatedly call a function from itself, unexpectedly leading to potentially disastrous results. The following are places
that are at risk of reentrancy: `LimitOrderRouter.executeOrders()`, `withdrawConveyorFees()`.


### Resolution

Logic to stop reentrancy has been added to `LimitOrderRouter.executeOrders()` and `withdrawConveyorFees()`. 

```solidity


    ///@notice Modifier to restrict reentrancy into a function.
    modifier nonReentrant() {
        if (reentrancyStatus == true) {
            revert Reentrancy();
        }
        reentrancyStatus = true;
        _;
        reentrancyStatus = false;
    }

    
    function executeOrders(bytes32[] calldata orderIds) external nonReentrant {
        
        //--snip--
    }

```


```solidity

    ///@notice Function to withdraw owner fee's accumulated
    function withdrawConveyorFees() external {
        if (reentrancyStatus == true) {
            revert Reentrancy();
        }
        reentrancyStatus = true;
   //--snip--     
```

# QSP-9 Not Cancelling Order as Expected ✅
### Description
A few code comments state that orders should be canceled in certain cases while the implementation does not cancel them.

### Resolution
Comments referring to order cancellation in these instances have been removed or cancellation logic has been added.

# QSP-10 Granting Insufficient Gas Credit to the Executor ✅

### Description
The calculateExecutionGasConsumed() function returns the gas difference of the initialTxGas and the current gas retrieved by the gas() call. The returned value is the
gas without multiplying it with the gas price. The calculateExecutionGasCompensation() function uses the returned gas value directly to calculate the gasDecrementValue. The
gasDecrementValue does not take the gas price into account either. Consequently, the executor will not get enough gas compensation with the current implementation.

### Resolution
The `calculateExecutionGasConsumed()` function was patched to multiply the gas price with the execution gas to decrement the correct amount of gas from the gasCredit balance and pay the off-chain executor. 


# QSP-11 Integer Overflow / Underflow ✅
### Description
Description: Integer overflow/underflow occurs when an integer hits its bit-size limit. Every integer has a set range; the value loops back around when that range is passed. A clock is a good
analogy: at 11:59, the minute hand goes to 0, not 60, because 59 is the most significant possible minute.
We noticed that the ConveyorMath library implements changes from the ABDK library and introduced several issues because the overflow protection on the original library would work only on
the signed integers or with 128 bits. The overflow can lead to a miscalculation of the fees and rewards in the SwapRouter contract.

### Resolution
All reccomendations have been implemented in their corresponding functions. 

# QSP-12 Updating Order Performs Wrong Total Order Quantity Accounting ✅
### Description
The updateOrders() function first retrieves the value for the oldOrder.tokenIn, then performs adjustments depending on whether the new order has a higher or lower order quantity. The
first issue with the function is that the else branch of the adjustment code is incorrect. If we assume the old value was 100 and the new value is 50, the total will be updated by += 100 - 50,
i.e. an increase by 50 instead of a decrease. While this code path is exercised in a test, the total order value is never checked to be equal to the expected value.
Additionally, the function updates the total order quantity with a call to updateTotalOrdersQuantity(newOrder.tokenIn, ...). Since it is never checked that the tokenIn member of
the old and new order are the same, this could update some completely unrelated token order quantity.

### Resolution

The updated order quantity now calculates the correct value.


```solidity

totalOrdersValue += newQuantity;
totalOrdersValue -= oldOrder.quantity;

```
# QSP-13 Not Always Taking Beacon Reward Into Account ✅
### Description
In the TaxedTokenLimitOrderExecution and TokenToTokenLimitOrderExecution contracts, the _executeTokenToTokenOrder() functions will always return a zero
amount beaconReward when order.tokenIn != WETH. Note that the function _executeSwapTokenToWethOrder() has the logic for computing beaconReward in it but the
beaconReward value is not returned as part of the function. The _executeTokenToTokenOrder() will need to get the beaconReward value from the
_executeSwapTokenToWethOrder() function.

### Resolution
The taxed execution contracts have been removed with the new architecture. `_executeSwapTokenToWethOrder()` Now returns the conveyor/beacon reward. Further, the execution tests now have assertions validating executor payment after execution has completed.

# QSP-14 Denial of Service Due to Unbound Iteration ✅
### Description
Description: There is a limit on how much gas a block can execute on the network. It can consume more gas than the network limit when iterating over an unbounded list. In that case, the
transaction will never work and block the service. The following is the list of places that are at risk:

### Resolution
#### 1.)
Modified `getAllOrderIds` to use an `offset`, and `length` parameter to index `addressToAllOrderIds` array from a specified position with a fixed return data `length`.
```solidity
function getOrderIds(
        address owner,
        OrderType targetOrderType,
        uint256 orderOffset,
        uint256 length
    ) public view returns (bytes32[] memory) {
        bytes32[] memory allOrderIds = addressToAllOrderIds[owner];

        uint256 orderIdIndex = 0;
        bytes32[] memory orderIds = new bytes32[](allOrderIds.length);

        uint256 orderOffsetSlot;
        assembly {
            //Adjust the offset slot to be the beginning of the allOrderIds array + 0x20 to get the first order + the order Offset * the size of each order
            orderOffsetSlot := add(
                add(allOrderIds, 0x20),
                mul(orderOffset, 0x20)
            )
        }

        for (uint256 i = 0; i < length; ++i) {
            bytes32 orderId;
            assembly {
                //Get the orderId at the orderOffsetSlot
                orderId := mload(orderOffsetSlot)
                //Update the orderOffsetSlot
                orderOffsetSlot := add(orderOffsetSlot, 0x20)
            }

            OrderType orderType = addressToOrderIds[owner][orderId];

            if (orderType == targetOrderType) {
                orderIds[orderIdIndex] = orderId;
                ++orderIdIndex;
            }
        }

        //Reassign length of each array
        assembly {
            mstore(orderIds, orderIdIndex)
        }

        return orderIds;
    }
```

#### 2.)
The number of `dexes` deployed in the constructor of the `SwapRouter` will never be anywhere from `3-15` depending on the chain. This will be sufficiently small to not exceed the block gas limit in `getAllPrices` when iterating through the dexes.
# QSP-15 Missing Input Validation ✅
### Description
1.) The following has been added to `_removeOrderFromSystem` in both `LimitOrderBook` and `SandboxLimitOrderBook`
```solidity
        ///@notice If the order has already been removed from the contract revert.
        if (order.orderId == bytes32(0)) {
            revert DuplicateOrderIdsInOrderGroup();
        }
```
2.)
```solidity
    ///@notice Function to transfer ownership of the contract.
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) {
            revert InvalidAddress();
        }
        tempOwner = newOwner;
    }
```
3.) The following has been added to `executeOrders`
```solidity
 for (uint256 i = 0; i < orderIds.length; ) {
            orders[i] = getLimitOrderById(orderIds[i]);
            if (orders[i].orderId == bytes32(0)) {
                revert OrderDoesNotExist(orderIds[i]);
            }
            unchecked {
                ++i;
            }
        }
```
4.) 
```solidity
constructor(
        bytes32[] memory _deploymentByteCodes,
        address[] memory _dexFactories,
        bool[] memory _isUniV2
    ) {
        ///@notice Initialize DEXs and other variables
        for (uint256 i = 0; i < _deploymentByteCodes.length; ++i) {
            if (i == 0) {
                require(_isUniV2[i], "First Dex must be uniswap v2");
            }
            require(
                _deploymentByteCodes[i] != bytes32(0) &&
                    _dexFactories[i] != address(0),
                "Zero values in constructor"
            );
            dexes.push(
                Dex({
                    factoryAddress: _dexFactories[i],
                    initBytecode: _deploymentByteCodes[i],
                    isUniV2: _isUniV2[i]
                })
            );

            ///@notice If the dex is a univ3 variant, then set the uniswapV3Factory storage address.
            if (!_isUniV2[i]) {
                uniswapV3Factory = _dexFactories[i];
            }
        }
    }
```
5.)
```solidity

    constructor(address _gasOracleAddress) {
        require(_gasOracleAddress != address(0), "Invalid address");
        gasOracleAddress = _gasOracleAddress;

        (, int256 answer, , , ) = IAggregatorV3(gasOracleAddress)
            .latestRoundData();
        meanGasPrice = uint256(answer);
        cumulativeSum = meanGasPrice;
        lastGasOracleTimestamp = block.timestamp;
    }
```
6.)
`SandboxLimitOrderBook`
```solidity
constructor(
        address _conveyorGasOracle,
        address _limitOrderExecutor,
        address _weth,
        address _usdc,
        uint256 _sandboxLimitOrderExecutionGasCost
    ) ConveyorGasOracle(_conveyorGasOracle) {
        require(
            _limitOrderExecutor != address(0),
            "limitOrderExecutor address is address(0)"
        );
        WETH = _weth;
        USDC = _usdc;
        LIMIT_ORDER_EXECUTOR = _limitOrderExecutor;
        SANDBOX_LIMIT_ORDER_EXECUTION_GAS_COST = _sandboxLimitOrderExecutionGasCost;
        CONVEYOR_GAS_ORACLE = _conveyorGasOracle;

        SANDBOX_LIMIT_ORDER_ROUTER = address(
            new SandboxLimitOrderRouter(_limitOrderExecutor, address(this))
        );
    }
```
`LimitOrderBook`
```solidity
constructor(
        address _conveyorGasOracle,
        address _limitOrderExecutor,
        address _weth,
        address _usdc,
        uint256 _limitOrderExecutionGasCost

    ) {

        require(
            _limitOrderExecutor != address(0),
            "limitOrderExecutor address is address(0)"
        );

        WETH = _weth;
        USDC = _usdc;
        LIMIT_ORDER_EXECUTOR = _limitOrderExecutor;
        LIMIT_ORDER_EXECUTION_GAS_COST = _limitOrderExecutionGasCost;
        CONVEYOR_GAS_ORACLE = _conveyorGasOracle;
    }
```
7.) This validation is happening in the `ConveyorExecutor` Constructor prior to deploying the `LimitOrderRouter`
```solidity
constructor(
        address _weth,
        address _usdc,
        address _limitOrderQuoterAddress,
        bytes32[] memory _deploymentByteCodes,
        address[] memory _dexFactories,
        bool[] memory _isUniV2,
        address _chainLinkGasOracle,
        uint256 _limitOrderExecutionGasCost,
        uint256 _sandboxLimitOrderExecutionGasCost
    ) SwapRouter(_deploymentByteCodes, _dexFactories, _isUniV2) {
        require(
            _chainLinkGasOracle != address(0),
            "Invalid gas oracle address"
        );

        require(_weth != address(0), "Invalid weth address");
        require(_usdc != address(0), "Invalid usdc address");
        require(
            _limitOrderQuoterAddress != address(0),
            "Invalid LimitOrderQuoter address"
        );

        USDC = _usdc;
        WETH = _weth;
        LIMIT_ORDER_QUOTER = _limitOrderQuoterAddress;
        LIMIT_ORDER_EXECUTION_GAS_COST = _limitOrderExecutionGasCost;
        SANDBOX_LIMIT_ORDER_EXECUTION_GAS_COST = _sandboxLimitOrderExecutionGasCost;

        SANDBOX_LIMIT_ORDER_BOOK = address(
            new SandboxLimitOrderBook(
                _chainLinkGasOracle,
                address(this),
                _weth,
                _usdc,
                _sandboxLimitOrderExecutionGasCost
            )
        );

        ///@notice Assign the SANDBOX_LIMIT_ORDER_ROUTER address
        SANDBOX_LIMIT_ORDER_ROUTER = ISandboxLimitOrderBook(
            SANDBOX_LIMIT_ORDER_BOOK
        ).getSandboxLimitOrderRouterAddress();

        LIMIT_ORDER_ROUTER = address(
            new LimitOrderRouter(
                SANDBOX_LIMIT_ORDER_BOOK, ///@notice The SandboxLimitOrderBook inherits the conveyor gas oracle.
                _weth,
                _usdc,
                address(this),
                _limitOrderExecutionGasCost
            )
        );

        ///@notice assign the owner address
        owner = msg.sender;
    }
```
8.) This function has moved into the `ConveyorExecutor`, below is the resolved code.
```solidity
function depositGasCredits() public payable returns (bool success) {
        if (msg.value == 0) {
            revert InsufficientMsgValue();
        }
        ///@notice Increment the gas credit balance for the user by the msg.value
        uint256 newBalance = gasCreditBalance[msg.sender] + msg.value;

        ///@notice Set the gas credit balance of the sender to the new balance.
        gasCreditBalance[msg.sender] = newBalance;

        ///@notice Emit a gas credit event notifying the off-chain executors that gas credits have been deposited.
        emit GasCreditEvent(msg.sender, newBalance);

        return true;
    }
```
9.) Ref `4` for resolved code.
10.) Added assertion to `calculateFee`
```solidity
uint128 calculated_fee_64x64;
        if (amountIn == 0) {
            revert AmountInIsZero();
        }
```
11.) Not Applicable in the current architecture. Below is the Quoter constructor.
```solidity
constructor(address _weth) {
        require(_weth != address(0), "Invalid weth address");
        WETH = _weth;
    }
```
12.) Ref `7` for resolved constructor. 
### Resolution

# QSP-16 Gas Oracle Reliability ✅
### Description
1. Chainlink updates the feeds periodically (heartbeat idle time). The application should check that the timestamp of the latest answer is updated within the latest
heartbeat or within the time limits acceptable for the application (see: Chainlink docs). The GasOracle.getGasPrice() function does not check the timestamp of the
answer from the IAggregatorV3(gasOracleAddress).latestRoundData() call.
2. The "Fast Gas Data Feed" prices from Chainlink can be manipulated according to their docs. The application should be designed to detect gas price volatility or
malicious activity.


### Resolution
The GasOracle now stores a moving average over a 24 hour time horizon, adjusting the average everytime the gas oracle is called, accounting for any volitility or stale gas prices. 

```solidity

contract GasOracle {
    //--snip--

    uint256 constant timeHorizon = 86400;
    //--snip--


    if (!(block.timestamp == lastGasOracleTimestamp)) {
            (, int256 answer, , , ) = IAggregatorV3(gasOracleAddress)
                .latestRoundData();

            uint256 gasPrice = uint256(answer);
            if (block.timestamp - lastGasOracleTimestamp > timeHorizon) {
                cumulativeSum = meanGasPrice + gasPrice;
                arithmeticscale = 2;
                meanGasPrice = cumulativeSum / arithmeticscale;
            } else {
                cumulativeSum += gasPrice;
                arithmeticscale++;
                meanGasPrice = cumulativeSum / arithmeticscale;
            }
            emit MeanGasPriceUpdate(
                block.number,
                block.timestamp,
                gasPrice,
                meanGasPrice
            );
        }

}
```


# QSP-17 Math Function Returns Wrong Type ✅
Severity: 🟡Low Risk🟡
## Description
Under the assumption that the function `divUU128x128()` should return a `128.128` fixed point number, this function does not return the correct value.
### Resolution Details
This function has been removed from the codebase as we are no longer using it in the core contracts.


# QSP-18 Individual Order Fee Is Not Used in Batch Execution ✅

File(s) affected: TokenToWethLimitOrderExecution.sol
**Description**: In TokenToWethLimitOrderExecution.sol#L365, getAllPrices() is using the first order's order.feeIn to compute uniswap prices for all of the orders in the batch.
However, different orders are not guaranteed to have the same feeIn. Thus, the computed result may not apply to all orders in the batch.
**Recommendation**: Change the logic to use each individual order's feeIn or check that they all have the same feeIn value, e.g. in LimitOrderRouter._validateOrderSequencing().

### Resolution Details
Updated _validateOrderSequencing() to check for congruent `feeIn` and `feeOut`. Added tests `testFailValidateOrderSequence_IncongruentFeeIn` and  `testFailValidateOrderSequence_IncongruentFeeOut`.

# QSP-19 Locking the Difference Between `beaconReward` and `maxBeaconReward` in the Contract ✅
Severity: 🔵Informational🔵
## Description: 
The code has the concept of a `maxBeaconReward` to cap the max beacon reward sent to the executor. So whenever the raw `beaconReward` is greater than the `maxBeaconReward`, the executor will get the `maxBeaconReward`. However, the implementation will lock the difference between the two in the contract.
### Resolution Details
This issue has been resolved by subtracting the `amountOutInWeth` by the beaconReward after the cap has been computer. Along with this we decided to remove the maxBeaconReward for all order types except stoplosses.


## QSP-19_1
`TaxedTokenLimitOrderExecution._executeTokenToWethTaxedSingle()`: The function calls the `_executeTokenToWethOrder()` function on L133 and the `_executeTokenToWethOrder() `function will return `uint256(amountOutWeth - (beaconReward + conveyorReward))` (L192) as the `amountOut`. The `amountOut` is the final amount transferred to the order's owner. Later on L148-150, the raw `beaconReward` is capped to the `maxBeaconReward`. The difference will be left and locked in the contract.

### Resolution
The contract architecture change from batch execution to linear execution remvoved the need for a TaxedTokenLimitOrderExecution contract. A single taxed order from Token -> WETH will now be executed by the contract `LimitOrderExecutor#L52` within the function `executeTokenToWethOrders`. The resolution to the locked beacon reward issue within the function is addressed in **QSP-19_6**.
## QSP-19_2 
`TaxedTokenLimitOrderExecution._executeTokenToTokenTaxedSingle()`: The function calls `_executeTokenToTokenOrder().` The raw `beaconReward` will also be part of the deduction in `_executeTokenToTokenOrder()` (L357): `amountInWethToB = amountIn - (beaconReward + conveyorReward)`. The `maxBeaconReward` cap is applied later, and the difference will be left locked in the contract.
### Resolution
The contract architecture change from batch execution to linear execution remvoved the need for a TaxedTokenLimitOrderExecution contract. A single taxed order from Token -> Token will now be executed by the contract `LimitOrderExecutor#L220` within the function `executeTokenToTokenOrders`. The resolution to the locked beacon reward issue within the function is addressed in **QSP-19_4**.
## QSP-19_3
TokenToTokenLimitOrderExecution._executeTokenToTokenSingle(): The function calls the _executeTokenToTokenOrder(). The raw beaconReward will be deducted when calculating the amountInWethToB. Later in _executeTokenToTokenSingle(), the maxBeaconReward is applied to the beaconReward. The difference
between the beaconReward and maxBeaconReward will be left in the contract.
### Resolution
This function has been removed as it is no longer needed with a linear execution contract architecture. A single order from Token-> Token will now be executed by the contract `LimitOrderExecutor#L220` within the function `executeTokenToTokenOrders`. The resolution to the locked beacon reward issue within the function is addressed in **QSP-19_4**.
## QSP-19_4
`TokenToTokenLimitOrderExecution._executeTokenToTokenBatchOrders()`: The function calls `_executeTokenToTokenBatch()`. In the
`_executeTokenToTokenBatch()` function, the raw `beaconReward` is deducted when calculating the `amountInWethToB`. Later in the `_executeTokenToTokenBatchOrders()` function, the `maxBeaconReward` is applied to the `totalBeaconReward`. The difference between the `totalBeaconReward` and `maxBeaconReward` will be left in the contract.
### Resolution
The function `TokenToTokenLimitOrderExecution._executeTokenToTokenBatchOrders()` has been replaced with `LimitOrderExecutor#L222executeTokenToTokenOrders()` as a result of changing to a linear execution architecture. The function similarly calculates the `maxBeaconReward` `#L256-257` and calls `_executeTokenToTokenOrder#L278` passing in the capped beacon reward.
#### Case Token-Token.) 
The function calls `_executeSwapTokenToWethOrder#L329` and returns the `amountInWethToB` decremented by the `maxBeaconReward` if instantiated. The fix can be referenced at `LimitOrderExecutor#L190-217`. 
#### Case WETH-Token.) 
Since WETH is the input token no swap is needed. The function `_executeTokenToTokenOrder#L341` calls `transferTokensToContract` and decrements the value `amountInWethToB` by the `maxBeaconReward` if instantiated. The fix can be referenced in `LimitOrderExecutor#L341-363`.
## QSP-19_5 
`TokenToWethLimitOrderExecution._executeTokenToWethSingle()`: The function calls `_executeTokenToWethOrder()`. The `_executeTokenToWethOrder()` will deduct the raw `beaconReward` when returning the `amountOut` value. Later, the `_executeTokenToWethSingle()` function caps the `beaconReward` to `maxBeaconReward`. The difference between the `beaconReward` and `maxBeaconReward` will be left in the contract. 

### Resolution
This function has been removed as it is no longer needed with a linear execution contract architecture. A single order from Token-> WETH will now be executed by the contract `LimitOrderExecutor#L52` within the function `executeTokenToWethOrders`. The resolution to the locked beacon reward issue within the function is addressed in **QSP-19_6**.

## QSP-19_6 
`TokenToWethLimitOrderExecution._executeTokenToWethBatchOrders()`: The function calls the `_executeTokenToWethBatch()` function. The `_executeTokenToWethBatch()` will deduct the raw `beaconReward` when returning the `amountOut` value. Later, the `_executeTokenToWethBatchOrders()` function caps the `totalBeaconReward` to `maxBeaconReward`. The difference between the `totalBeaconReward` and `maxBeaconReward` will be left in the contract.

### Resolution

The function `TokenToWethLimitOrderExecution._executeTokenToWethBatchOrders()` is no longer used with the changes to a simpler linear execution architecture. All orders from Token -> Weth will now be executed at the top level by `LimitOrderExecutor#L52executeTokenToWethOrders`. This function calculates the `maxBeaconReward` `LimitOrderExecutor#L72` and calls `_executeTokenToWethOrder#L97` passing in the `maxBeaconReward` as a parameter. `_executeTokenToWethOrder` calls `_executeSwapTokenToWethOrder#L141` with the `maxBeaconReward` as a parameter and the returned `amountOutWeth` value is decremented by the `beaconReward` after the `beaconReward` has been capped. The fix can be referenced at 

`ConveyorExecutor#L476`
```solidity
        ///@notice Calculate the conveyorReward and executor reward.
        (conveyorReward, beaconReward) = ConveyorFeeMath.calculateReward(
            protocolFee,
            amountOutWeth
        );
        ///@notice If the order is a stoploss, and the beaconReward surpasses 0.05 WETH. Cap the protocol and the off chain executor at 0.05 WETH.
        if (order.stoploss) {
            if (STOP_LOSS_MAX_BEACON_REWARD < beaconReward) {
                beaconReward = STOP_LOSS_MAX_BEACON_REWARD;
                conveyorReward = STOP_LOSS_MAX_BEACON_REWARD;
            }
        }

        ///@notice Get the AmountIn for weth to tokenB.
        amountOutWeth = amountOutWeth - (beaconReward + conveyorReward);
```


# QSP-20 Inaccurate Array Length ✅ (Needs tests to validate expected behavior)
Severity: Informational Status: Unresolved

File(s) affected: LimitOrderBatcher.sol, OrderBook.sol
**Description**: Some functions return arrays that are padded with empty elements. The caller of those functions will need to be aware of this fact to not accidentally treat the padding as real data. The following is a list of functions that have this issue:
1. OrderBook.getAllOrderIds(): The impact is unclear, as the function is only used in the test contracts.

2. LimitOrderBatcher.batchTokenToTokenOrders(): The function is called by TokenToTokenLimitOrderExecution.executeTokenToTokenOrders(). Fortunately, the
implementation of executeTokenToTokenOrders() seems to be aware of the fact that batches can be empty.

**Recommendation**: Either get an exact array length and allocate the array with the correct size or try to override the array length before returning the array. Otherwise, consider adding a warning to the above functions to ensure callers are aware of the returned array potentially containing empty elements.
While newer solidity versions no longer allow assigning the array length directly, it is still possible to do so using assembly:

```solidity
assembly {
    mstore(<:your_array_var>, <:reset_size>)
}
```

### Resolution

In `OrderBook.getAllOrderIds()` assembly is used to resize the array after it is populated. Batching functionality was removed so the issue in `LimitOrderBatcher.batchTokenToTokenOrders()` no longer exists.



# QSP-21 `TaxedTokenLimitOrderExecution` Contains Code for Handling Non-Taxed Orders ✅

Severity: 🔵Informational🔵

## Description: 
The function `_executeTokenToTokenOrder()` checks whether the order to execute is taxed. In case it is not, the tokens for the order are transferred to the `SwapRouter`contract. When actually executing the swap in `_executeSwapTokenToWethOrder()`, the swap is performed using the order.owner as sender, i.e. the tokens will be sent again from that address. Since the function is typically only called from code paths where orders are taxed, the best case scenario is that `TaxedTokenLimitOrderExecution.sol#L323-326` is dead code. In case somebody calls this function manually with a non-taxed order, it might lead to tokens being sent erroneously to the SwapRouter.

### Resolution
This code has been removed with the new contract architecture for linear execution. Taxed orders now follow the same execution flow as untaxed orders dependent on whether the swap is happening on Token-> Weth or Token->Token.


## QSP-22 Unlocked Pragma ✅
Severity: 🔵Informational🔵
## Description: 
Every Solidity file specifies in the header a version number of the format pragma solidity (^)0.8.*. The caret (^) before the version number implies an unlocked pragma,
meaning that the compiler will use the specified version and above, hence the term "unlocked".
### Resolution
Locked all core contracts at solidity v0.8.16.

# QSP-23 Allowance Not Checked when Updating Orders ✅
Severity: 🔵Informational🔵
## Description: 
When placing an order, the contract will check if users set a high enough allowance to the ORDER_ROUTER contract (L216). However, this is not checked when updating an order in
the function updateOrder().
### Resolution
Added a check that ensures the allowance of the sender on the `LimitOrderExecutor` contract >= the `newOrder.quantity`. Reference `OrderBook.sol#L277-281` for the fix:
```solidity
        ///@notice If the total approved quantity is less than the newOrder.quantity, revert.
        if (totalApprovedQuantity < newOrder.quantity) {
            revert InsufficientAllowanceForOrderUpdate();
        }
```
Test Reference `OrderBook.t.sol#L363-401`:
```solidity
    ///@notice Test fail update order insufficient allowance
    function testFailUpdateOrder_InsufficientAllowanceForOrderUpdate(
        uint128 price,
        uint64 quantity,
        uint128 amountOutMin,
        uint128 newPrice,
        uint128 newAmountOutMin
    ) public {
        cheatCodes.deal(address(this), MAX_UINT);
        IERC20(swapToken).approve(address(limitOrderExecutor), quantity);
        cheatCodes.deal(address(swapHelper), MAX_UINT);
        swapHelper.swapEthForTokenWithUniV2(100000000000 ether, swapToken);

        //create a new order
        OrderBook.LimitOrder memory order = newOrder(
            swapToken,
            wnato,
            price,
            quantity,
            amountOutMin
        );

        //place a mock order
        bytes32 orderId = placeMockOrder(order);

        //create a new order to replace the old order
        OrderBook.LimitOrder memory updatedOrder = newOrder(
            swapToken,
            wnato,
            newPrice,
            quantity + 1, //Change the quantity to more than the approved amount
            newAmountOutMin
        );

        updatedOrder.orderId = orderId;

        //submit the updated order should revert since approved quantity is less than order quantity
        orderBook.updateOrder(updatedOrder);
    }
```


# QSP-24 Incorrect Restriction in fromUInt256 ✅
Severity: 🔵Informational🔵
## Description: 
In the function `fromUInt256()`, if the input `x` is an unsigned integer and `x <= 0xFFFFFFFFFFFFFFFF`, then after `x << 64`, it will be less than or equal to `MAX64.64`. However
the restriction for `x` is set to `<= 0x7FFFFFFFFFFFFFFF` in the current implementation.

### Resolution
Changed the require statement to the reccomended validation logic. Reference `ConveyorMath.sol#L20-25`.
```solidity
function fromUInt256(uint256 x) internal pure returns (uint128) {
    unchecked {
        require(x <= 0xFFFFFFFFFFFFFFFF);
        return uint128(x << 64);
    }
}
```


# QSP-25 Extremely Expensive Batch Execution for Uniswap V3 ✅
Severity: 🟢Undetermined🟢
File(s) affected: `LimitOrderBatcher.sol`, `SwapRouter.sol`
## Description: 
According to the discussion with the team, the motivation for executing orders in batches is to save gas by reducing the number of swaps. However, when it comes to Uniswap V3, the code heavily relies on the `QUOTER.quoteExactInputSingle()` call to get the output amount of the swap. Unfortunately, the `QUOTER.quoteExactInputSingle()` is as costly as a real swap because it is performing the swap and then force reverting to undo it (see: code and doc). `QUOTER.quoteExactInputSingle()` is called in `SwapRouter.getNextSqrtPriceV3()`, `LimitOrderBatcher.calculateNextSqrtPriceX96()`, and `LimitOrderBatcher.calculateAmountOutMinAToWeth()`.
### Resolution
Changes made to mitigate Gas consumption in execution:
As per the reccomendation of the quant stamp team we changed the execution architecture of the contract to a stricly linear flow. The changes to linear execution architecture immediately reduced the gas consumption overall, most significantly when a V3 pool was utilized during execution because of a reduced amount of calls to the quoter. Further, we eliminated using the v3 quoter completely from the contract, and built our own internal logic to simulate the amountOut yielded on a V3 swap. Reference `Contract Architecture Changes/Uniswap V3` for a detailed report of the code, and it's implementation throughout the contract. 

Relevant Gas Snapshot Post Changes:
```js
╭──────────────────────────────────────────────────────────────┬─────────────────┬────────┬────────┬────────┬─────────╮
│ src/test/SwapRouter.t.sol:LimitOrderExecutorWrapper contract ┆                 ┆        ┆        ┆        ┆         │
╞══════════════════════════════════════════════════════════════╪═════════════════╪════════╪════════╪════════╪═════════╡
│ Deployment Cost                                              ┆ Deployment Size ┆        ┆        ┆        ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ 2805140                                                      ┆ 14741           ┆        ┆        ┆        ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ Function Name                                                ┆ min             ┆ avg    ┆ median ┆ max    ┆ # calls │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ _swap                                                        ┆ 76694           ┆ 85391  ┆ 85391  ┆ 94089  ┆ 2       │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ calculateV2SpotPrice                                         ┆ 11103           ┆ 22522  ┆ 22741  ┆ 30613  ┆ 7       │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ calculateV3SpotPrice                                         ┆ 22219           ┆ 25854  ┆ 25854  ┆ 29489  ┆ 2       │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ swapV2                                                       ┆ 33994           ┆ 48468  ┆ 39571  ┆ 80739  ┆ 4       │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ swapV3                                                       ┆ 101887          ┆ 182907 ┆ 182907 ┆ 263927 ┆ 2       │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ uniswapV3SwapCallback                                        ┆ 815             ┆ 22480  ┆ 32084  ┆ 35159  ┆ 5       │
╰──────────────────────────────────────────────────────────────┴─────────────────┴────────┴────────┴────────┴─────────╯
╭────────────────────────────────────────────────────┬─────────────────┬───────┬────────┬───────┬─────────╮
│ src/LimitOrderQuoter.sol:LimitOrderQuoter contract ┆                 ┆       ┆        ┆       ┆         │
╞════════════════════════════════════════════════════╪═════════════════╪═══════╪════════╪═══════╪═════════╡
│ Deployment Cost                                    ┆ Deployment Size ┆       ┆        ┆       ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ 3263478                                            ┆ 16664           ┆       ┆        ┆       ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ Function Name                                      ┆ min             ┆ avg   ┆ median ┆ max   ┆ # calls │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ _findBestTokenToTokenExecutionPrice                ┆ 5347            ┆ 5353  ┆ 5347   ┆ 5401  ┆ 21      │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ _findBestTokenToWethExecutionPrice                 ┆ 2350            ┆ 2362  ┆ 2350   ┆ 2377  ┆ 11      │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ _initializeTokenToTokenExecutionPrices             ┆ 8889            ┆ 10998 ┆ 11902  ┆ 11902 ┆ 10      │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ _initializeTokenToWethExecutionPrices              ┆ 4623            ┆ 4623  ┆ 4623   ┆ 4623  ┆ 4       │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ calculateAmountOutMinAToWeth                       ┆ 4006            ┆ 9066  ┆ 6011   ┆ 19654 ┆ 22      │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ simulateTokenToTokenPriceChange                    ┆ 4481            ┆ 9253  ┆ 4481   ┆ 32449 ┆ 21      │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ simulateTokenToWethPriceChange                     ┆ 6220            ┆ 14629 ┆ 6369   ┆ 24576 ┆ 11      │
╰────────────────────────────────────────────────────┴─────────────────┴───────┴────────┴───────┴─────────╯
```

# QSP-26 Issues in Maximum Beacon Reward Calculation ✅
### Resolution
We decided to remove the `alphaX` and `maxBeaconReward` functions from the contract because of the gas consumed from the computation. We also decided capping the reward was not necessary for any limit order other than a stop loss. We added a constant: 
```solidity
uint128 constant STOP_LOSS_MAX_BEACON_REWARD = 50000000000000000;
```
This constant is used in place of the `maxBeaconReward` in the case of stoploss orders. 

# QSP-27 Verifier's Dilemma ✅
`Old System`
For order execution, the gas price that can be used is capped so that an off-chain executor can assign the max gas to avoid being frontrun by another off-chain executor. The cap is 1.75% above the Chainlink fast gas oracle. The Chainlink oracle's gas price can deviate from the real competitive gas price by 25% before an update. If the gas oracle is 25% lower than
the competitive gas price, the execution transaction gas price is still priced at a competitive rate. If the gas oracle is 25% higher than the competitive gas price, the execution gas price will be faster than the current competitive rate. At all times, the execution transaction's gas price will be competitve.

Since the gas price is an exact value, searchers can not monitor the mempool and front run the transaction with a higher gas price. This effecively eliminates the verifier's delimma from the protocol, incentivizing the off-chain executor to be the first to compute the execution opportunity and submit a transaction. Any while miners/block builders can order a block as they desire there is not an incentive to order one transaction in front of the other, allowing the first to submit the transaction to be included in most cases. There is still a chance that block builders (or validators, depending on the chain) could reorder transactions before including them in the block. Off-chain executors are encouraged to use Flashbots or equivalent, for chains that have private relays to further avoid potential frontrunning. 

`New System`
The new system will not cap the `tx.gasPrice`. Instead, on chains where possible the open source executor will use relayers for `tx` obfuscation, and on chains without relayers will use `pga` mechanics. This was decided to give the executor maximum flexibility on pathing allowing them to pass `SandboxLimitOrders` liquidity through convex pathing where there will likely be competition outside the network to capture mev opportunities. The executor gets to keep any profit above the `amountOutRequired` on the order, so we expect to see and employ complex strategies that would be severely handicapped by requiring any max `gasPrice`.

With that said, the owners of the `SandboxLimitOrders` being executed will only pay a maximum amount of gas compensation defined as an immutable variable in the `ConveyorExecutor` called `SANDBOX_LIMIT_ORDER_EXECUTION_GAS_COST`.


# QSP-28 Taxed Token Swaps Using Uniswap V3 Might Fail 🟡
This QSP has been acknowledged. The current taxed token tests in the codebase have been successfully executed on V3 Pools. The off-chain executor is able to call the node prior to execution, and should be able to determine if a taxed token execution will fail or not. In the case when a taxed token were to fail a v3 execution the off-chain executor can wait until a v2 pool becomes the most advantageous limit price to execute the Order. Further, we expect the majority of the limit orders on the protocol passing through the `SandboxLimitOrders` system since only `stoplosses` will be placed on the old system through the `ConveyorFinance` frontend interface.
# **Code Documentation**
Consider providing instructions on how to build and test the contracts in the README.  </br>
Consider providing a link in the code comment for the SwapRouter._getV2PairAddress() function (L1025-1045) on how the address is determined: Uniswap V2 Pair Address doc. ✅ </br>

The comment in LimitOrderRouter.sol#L416 (within the `_validateOrderSequencing()` function) does not match the implementation. Change it from "Check if thetoken tax status is the same..." to "Check if the buy/sell status is the same..." instead. ✅ </br>

The code documentation/comment in `LimitOrderBatcher.sol#L22` and `LimitOrderBatcher.sol#L35` for the `batchTokenToTokenOrders()` function seems inconsistent with the implementation. The comment states "Function to batch multiple token to weth orders together" and "Create a new token to weth batch order", but the function is token to "token" and not token to "weth". ✅ </br>

`LimitOrderBatcher.sol#L469` states, "If the order is a buy order, set the initial best price at 0". However, the implementation set the initial best price to the max of `uint256`. Similarly, L475 states, "If the order is a sell order, set the initial best price at max `uint256`". In contrast, the implementation sets the initial price to zero. The implementation seems correct, and the comment is misleading.  ✅ </br>

The code documentation for the following contracts seems misplaced: `TaxedTokenLimitOrderExecution`, `TokenToTokenLimitOrderExecution`, and `TokenToWethLimitOrderExecution`. They all have `@title SwapRouter` instead of each contract's documentation.  ✅ </br>

Fix the code documentation for the `ConveyorMath.add64x64()` function. L65 states that "helper to add two unsigened `128.128` fixed point numbers" while the functions add two `64.64` fixed point numbers instead. Also, there is a typo on the word "unsigened", which should be "unsigned".
Consider adding NatSpec documentation for the following functions in `ConveyorMath.sol`: `sub()`, `sub64UI()`, `abs()`, `sqrt128()`, `sqrt()`, and `sqrtBig()`. It is unclear which types they operate on (e.g., whether they should be fixed-point numbers).  ✅ </br>

Fix the code documentation for the `ConveyorMath.mul128x64()` function. **L130** states that "helper function to multiply two unsigned `64.64` fixed point numbers" while multiplying a `128.128` fixed point number with another `64.64` fixed-point number.  ✅ </br>

Add `@param` comment for the field `taxIn` of the struct Order **(L44-73)** in `OrderBook.sol`. ✅ </br>

Consider adding a warning for the `SwapRouter.calculateFee()` function that the amountIn can only be the amount **WETH (or 18 decimal tokens)**.  ✅</br>

The onlyOwner modifier implemented in the `LimitOrderExecution.sol` contracts has documentation that states that the modifier should be applied to the function `transferOwnership()`. As there is no transferOwnership() function in those contracts, either add one or remove it from the modifier documentation.  ✅ </br>

`ConveyorMath.mul128I()#L167`, **"multiply unsigned 64.64" should be "128.128"**.  ✅ </br>

`ConveyorMath.div128x128()#L213`, **"@return unsigned uint128 64.64" should be "128.128"**.  ✅ </br>

`ConveyorMath.divUI()#L229`, **"helper function to divide two 64.64 fixed point numbers" should be "... two integers"**.  ✅ </br>

`ConveyorMath.divUI128x128()#L310`, **"helper function to divide two unsigned 64.64 fixed point" should be "... two integers".**  ✅ </br>

`ConveyorMath.divUI128x128()#L313`, **"@return unsigned uint128 64.64 unsigned integer" should be "... uint256 128.128 fixed point number"**.  ✅ </br>
`ConveyorMath.divUU128x128()#L330`, **"@return unsigned 64.64" should be "... 128.128"**.  ✅ </br>

`TokenToWethLimitOrderExecution.sol#L349`, **the documentation is wrong, since the function only handles tokenA -> Weth**.  ✅ </br>

`TaxedTokenLimitOrderExecution.sol#L197`, **the documentation is wrong, since the function only handles tokenA -> Weth**.  ✅ </br>

### The following functions do not have any documentation: ✅ 
        `ConveyorTickMath.fromX96()`
        `ConveyorMath.sub()`
        `ConveyorMath.sub64UI()`
        `ConveyorMath.sqrt128()`
        `ConveyorMath.sqrt()`
        `ConveyorMath.sqrtBig()`
        `QuadruplePrecision.to128x128()`
        `QuadruplePrecision.fromInt()`
        `QuadruplePrecision.toUInt()`
        `QuadruplePrecision.from64x64()`
        `QuadruplePrecision.to64x64()`
        `QuadruplePrecision.fromUInt()`
        `QuadruplePrecision.from128x128()`
The `@return` documentation for the following functions is unclear:


       `ConveyorMath.mul64x64()` (expecting unsigned 64.64).
       `ConveyorMath.mul128x64() (expecting unsigned 128.128).
       `ConveyorMath.mul64U()` (expecting unsigned integer).
       `ConveyorMath.mul128U()` (expecting unsigned integer).
       

## Adherence to Best Practices**
Remove the unused function `OrderBook._resolveCompletedOrderAndEmitOrderFufilled()` (L371-392).  ✅ </br>

Remove the unused function `OrderBook.incrementTotalOrdersQuantity()` (L441-448).  ✅ </br>

`OrderBook.sol#L487`, replace the magic number 100 in the `_calculateMinGasCredits()` function with a named constant.  ✅ </br>

`OrderBook.sol#L505`, replace the magic number 150 in the `_hasMinGasCredits()` function with a named constant.  ✅ </br>

Consider setting the tempOwner to zero in the `LimitOrderRouter.confirmTransferOwnership()` function once the owner is set. By cleaning up the storage, the EVM will refund some gas.  ✅ </br>

Consider replacing the assembly block with simply `initalTxGas = gasleft()` in `LimitOrderRouter.sol#434-436`(within the `executeOrders()` function). The gas saved with the assembly is negligible (around 10). </br>

Consider removing the `LimitOrderBatcher._buyOrSell()` function. The code using this function can replace it simply with `firstOrder.buy on L44` and L207.  </br>

Consider renaming the `ConveyorMath.mul64I() (L149)` and the `ConveyorMath.mul128I()` (L171) functions to `mul64U()` and `mul128U()` instead. The functions handle unsigned integers instead of signed integers.  ✅ </br>

GasOracle.getGasPrice() tends to get called multiple times per execution. Consider whether it's possible to cache it to avoid multiple external calls.  ✅ </br>

`OrderBook.addressToOrderIds` seems unnecessary. It is used to check whether orders exist via: `bool orderExists = addressToOrderIds[msg.sender] [newOrder.orderId];`. This can also be done through `bool orderExists = orderIdToOrder[newOrder.orderId].owner == msg.sender`. </br>

`OrderBook.orderIdToOrder` should be declared as internal since the generated getter function leads to "stack too deep" errors when compiled without optimizations, which is required for collecting code coverage.  ✅ </br>

Consider using `orderNonce` as the orderId directly instead of hashing it with `block.timestamp`, since the orderNonce will already be unique. </br>
`OrderBook.sol#L177` and `LimitOrderRouter.sol#L285` perform a modulo operation on the block.timestamp and casts the result to uint32. A cast to uint32 willtruncate the value the same way the modulo operation does, which is therefore redundant and can be removed.  ✅ </br>

In `OrderBook.placeOrder()`, the local variables `orderIdIndex` and i will always have the same value. `orderIdIndex` can be removed and uses replaced by i.  ✅ </br>

Consider removing the `OrderBook.cancelOrder()` function, since the OrderBook.cancelOrders() contains nearly identical code. Additionally, to place an order, only the OrderBook.placeOrders() function exists, which makes the API inconsistent. </br>
`LimitOrderRouter.refreshOrder()#254` calls `getGasPrice()` in each loop iteration. Since the gas price does not change within a transaction, move this call out of the loop to save gas.  ✅ </br>

`LimitOrderRouter.refreshOrder()#277` sends the fees to the message sender on each loop. Consider accumulating the amount and use a single `safeTransferETH()` call at the end of the function.  ✅ </br>

`SwapRouter.sol` should implement the `IOrderRouter` interface explicitly to ensure the function signatures match. NA </br>

`SwapRouter._calculateV2SpotPrice()#L961` computes the Uniswap V2 token pair address manually and enforces that it is equal to the `IUniswapV2Factory.getPair()` immediately after. Since the addresses must match, consider using just the output of the call to `getPair()` and remove the manual address computation. The `getPair()` function returns the zero address in case the pair has not been created. </br>

SwapRouter._swapV3() makes a call to `getNextSqrtPriceV3()` to receive the `_sqrtPriceLimitX96` parameter that is passed to the pool's `swap() `function. Since the `getNextSqrtPriceV3()` function potentially also performs the expensive swap through the use of a `Quoter.quoteExactInputSingle()` call and the output amount of the swap will be checked by `uniswapV3SwapCallback()` anyway, consider using the approach of Uniswap V3's router and supply `(_zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1)` as the `_sqrtPriceLimitX96` parameter.  </br>

This would also allow removing the dependency on the Quoter contract for the SwapRouter contract.✅ </br>

Save the `uniV3AmountOut` amount in memory and set the contract storage back to 0 before returning the amount in `SwapRouter._swapV3()#L829` to save gas (see **EIP-1283**). ✅ </br>

The iQuoter member should be removed from the `*LimitOrderExecution.sol` contracts, since they are not used by the contracts and already inherited through `LimitOrderBatcher`. ✅ </br>

ConveyorMath.mul64x64#L125 uses an unclear require message that looks like a leftover from debugging. ✅ </br>

`SwapRouter.calculateReward()#L320`, **change (0.005-fee)/2+0.001*10**2 to ((0.005-fee)/2+0.001)*10**2** to avoid confusion about operator precedence.
`ConveyorMath.divUI()` and `ConveyorMath.divUU()` perform the same computation. Remove `divUI()`. ✅ </br>

`ConveyorMath.divUI128x128()` and `ConveyorMath.divUU128x128()` perform the same computation. Remove `divUI128x128()`. ✅ </br>

The function `mostSignificantBit()` exists in both ConveyorBitMath.sol and QuadruplePrecision.sol. Remove one of them. ✅ </br>

Typos in variables:

### Several variables contain the typo fufilled instead of fulfilled. Some of these are externally visible. ✅
    parameter _reciever in `SwapRouter._swapV2()` should be renamed to _receiver, the return variable amountRecieved should be amountReceived
    parameter _reciever in `SwapRouter._swapV3()` should be renamed to _receiver, the return variable amountRecieved should be amountReceived
    parameter _reciever in `SwapRouter._swap()` should be renamed to _receiver, the return variable amountRecieved should be amountReceived.
    
OrderBook.sol#L240 could use storage instead of memory to save gas. TODO: Ask about this one. </br>

Internal function `_executeSwapTokenToWethOrder()` in `TokenToWethLimitOrderExecution.sol` is never used and can be removed. ✅ </br>


