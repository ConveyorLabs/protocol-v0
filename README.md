# Conveyor Protocol v0
The core smart contracts of the Conveyor Limit Orders, and DEX Aggregator protocol.

## Build Instructions
First Clone the Repository
```sh
git clone https://github.com/ConveyorLabs/protocol-v0 && cd protocol-v0
```
### Run The Test Suite
```sh
 forge test -f <RPC_URL> --ffi 
 //Run a individual Test 
 forge test -f <RPC_URL> --ffi --match-contract LimitOrderRouterTest --match-test testOnlyEOA 

```
### Forge Coverage
```sh
 forge coverage -f <RPC_URL> --ffi 

```

### Forge Snapshot
```sh
 forge snapshot -f <RPC_URL> --ffi 

```

### Detailed Gas Report 
```sh
 forge test -f <RPC_URL> --ffi --gas-report

```


