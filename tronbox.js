const port = process.env.HOST_PORT || 9090;

module.exports = {
  networks: {
    mainnet: {
      // Don't put your private key here:
      privateKey: process.env.PRIVATE_KEY_MAINNET,
      /*
Create a .env file (it must be gitignored) containing something like

  export PRIVATE_KEY_MAINNET=4E7FEC...656243

Then, run the migration with:

  source .env && tronbox migrate --network mainnet

      */
      userFeePercentage: 0,
      feeLimit: 1000000000,
      fullHost: "https://api.trongrid.io",
      network_id: "1",
    },
    shasta: {
      privateKey: process.env.PRIVATE_KEY_SHASTA,
      userFeePercentage: 0,
      feeLimit: 15000000000,
      fullHost: "https://api.shasta.trongrid.io",
      network_id: "2",
    },
    nile: {
      privateKey: process.env.PRIVATE_KEY_NILE,
      userFeePercentage: 100,
      feeLimit: 1000 * 1e6,
      fullHost: "https://nile.trongrid.io",
      network_id: "3",
    },
    development: {
      // For tronbox/tre docker image
      privateKey:
        "eaced1c6a6d2bb39afa2ce07ef2d0ecbd934fa0fcbd5266e91ea06359f4cd26e",
      userFeePercentage: 0,
      feeLimit: 1000000000,
      fullHost: "http://127.0.0.1:" + port,
      network_id: "9",
    },
    compilers: {
      solc: {
        version: "0.8.20",
      },
    },
  },
  // solc compiler optimize
  solc: {
    optimizer: {
      enabled: true,
      runs: 100,
    },
    evmVersion: "istanbul",
    viaIR: true,
  },
};
