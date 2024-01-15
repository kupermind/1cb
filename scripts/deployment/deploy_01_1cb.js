/*global process*/

const { ethers } = require("hardhat");
const { LedgerSigner } = require("@anders-t/ethers-ledger");

async function main() {
    const useLedger = false;
    const derivationPath = "m/44'/60'/4'/0/0";
    const providerName = "mainnet";
    let EOA;

    const provider = await ethers.providers.getDefaultProvider(providerName);
    const signers = await ethers.getSigners();

    if (useLedger) {
        EOA = new LedgerSigner(provider, derivationPath);
    } else {
        EOA = signers[0];
    }
    // EOA address
    const deployer = await EOA.getAddress();
    console.log("EOA is:", deployer);

    console.log("1. EOA to deploy OneClickBond contract");
    const OneClickBond = await ethers.getContractFactory("OneClickBond");
    console.log("You are signing the following transaction: OneClickBond.connect(EOA).deploy()");
    const oneClickBond = await OneClickBond.connect(EOA).deploy();
    const result = await oneClickBond.deployed();

    // Transaction details
    console.log("Contract deployment: OneClickBond");
    console.log("Contract address:", oneClickBond.address);
    console.log("Transaction:", result.deployTransaction.hash);

    // Contract verification
    const execSync = require("child_process").execSync;
    execSync("npx hardhat verify --network " + providerName + " " + oneClickBond.address, { encoding: "utf-8" });
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
