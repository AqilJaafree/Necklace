# cross-chain-resolver-example

## Installation

Install example deps

```shell
pnpm install
```

Install [foundry](https://book.getfoundry.sh/getting-started/installation)

```shell
curl -L https://foundry.paradigm.xyz | bash
```

Install contract deps

```shell
forge install
```

## Running

To run tests you need to provide fork urls for Ethereum and Bsc

```shell
SRC_CHAIN_RPC=ETH_FORK_URL DST_CHAIN_RPC=BNB_FORK_URL pnpm test
```

### Public rpc

| Chain    | Url                          |
|----------|------------------------------|
| Ethereum | https://eth.merkle.io        |
| BSC      | wss://bsc-rpc.publicnode.com |

## Test accounts

### Available Accounts

```
(0) 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80: "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266" Owner of EscrowFactory
(1) 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d: "0x70997970C51812dc3A010C7d01b50e0d17dc79C8" User
(2) 0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a: "0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC" Resolver
```


```
# Package ID (main identifier)
PACKAGE_ID=0x2649d770fdeda172fc3854cfbd8893ed87eae6a9cf5dd9aa72ecf6d93d824dff

# Resolver Object ID (shared object)
RESOLVER_ID=0x4027e286ef74621fc458c90cba605c4beb2033ee73159367ec3ae0473159b19f

# Factory Object ID (shared object)  
FACTORY_ID=0x4a67a605d45460e06e1e3cacfc4ddc58eeb0cf9d67e9134ae35e5e46b7308ba0

# Your deployer address
DEPLOYER=0xb0be34d2874c522577ed7f49e6c11a12f5d550da871cd9a31f11e1f86d9da988
```