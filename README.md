# SelfWallet NOF Token Smart Contracts

[<img src="https://nof.selfwallet.io/assets/logo.png" width="100"/>](https://nof.selfwallet.io)

## Project Overview

NOF Token is an innovative token running on the TRON blockchain. It serves as a prototype for a future token that will be launched on its own blockchain. NOF is designed for fast and low-cost transactions with a transparent economic model.

## Repository Link

[GitHub Repository](https://github.com/selfwallet-ltd/tron-nof-token)

## Environment Setup for Linux

### Prerequisites

- Node.js v18+ (recommended)
- npm
- Git

### Checking and Installing Compiler Version 8.20

Ensure you have Solidity compiler version 8.20 installed:

```bash
npm list -g solc
```

If version 8.20 is not installed, install it globally:

```bash
npm install -g solc@0.8.20
```

Verify the installation:

```bash
npm list -g solc
```

### Updating Dependencies

Run the following command to update all dependencies:

```bash
npm update
```

### Installing TronBox

```bash
npm install -g tronbox
```

Verify the installation:

```bash
tronbox --version
```

### Compiling the Smart Contract

```bash
tronbox compile
```

### Bytecode Verification

After compilation, you can find the contract bytecode in `build/contracts/NOFToken.json`. To verify the bytecode with the deployed contract:

1. Open the JSON file:

   ```bash
   cat build/contracts/NOFToken.json | grep bytecode
   ```

2. Copy the `bytecode` field (excluding the "0x" prefix).

3. Compare it with the bytecode on TronScan:
   - Open [TronScan NOF Token](https://tronscan.org/#/token20/TFashaJpi88LkCrKAsjCEQFTKyRsEsmjZC)
   - Go to the "Code" tab
   - Compare the bytecode values

The bytecode must be identical without any modifications.

## License

[MIT](LICENSE)
