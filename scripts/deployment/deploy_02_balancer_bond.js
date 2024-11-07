/*global process*/

const { ethers } = require("hardhat");
const { LedgerSigner } = require("@anders-t/ethers-ledger");

async function main() {
    const fs = require("fs");
    const globalsFile = "globals.json";
    const dataFromJSON = fs.readFileSync(globalsFile, "utf8");
    let parsedData = JSON.parse(dataFromJSON);
    const useLedger = parsedData.useLedger;
    const derivationPath = parsedData.derivationPath;
    const providerName = parsedData.providerName;
    const gasPriceInGwei = parsedData.gasPriceInGwei;

    let networkURL = parsedData.networkURL;
    if (providerName === "mainnet") {
        if (!process.env.ALCHEMY_API_KEY_MAINNET) {
            console.log("set ALCHEMY_API_KEY_MAINNET env variable");
        }
        networkURL += process.env.ALCHEMY_API_KEY_MAINNET;
    } else if (providerName === "sepolia") {
        if (!process.env.ALCHEMY_API_KEY_SEPOLIA) {
            console.log("set ALCHEMY_API_KEY_SEPOLIA env variable");
            return;
        }
        networkURL += process.env.ALCHEMY_API_KEY_SEPOLIA;
    } else if (providerName === "polygon") {
        if (!process.env.ALCHEMY_API_KEY_MATIC) {
            console.log("set ALCHEMY_API_KEY_MATIC env variable");
        }
        networkURL += process.env.ALCHEMY_API_KEY_MATIC;
    } else if (providerName === "polygonAmoy") {
        if (!process.env.ALCHEMY_API_KEY_AMOY) {
            console.log("set ALCHEMY_API_KEY_AMOY env variable");
            return;
        }
        networkURL += process.env.ALCHEMY_API_KEY_AMOY;
    }

    const provider = new ethers.providers.JsonRpcProvider(networkURL);
    const signers = await ethers.getSigners();

    let EOA;
    if (useLedger) {
        EOA = new LedgerSigner(provider, derivationPath);
    } else {
        EOA = signers[0];
    }
    // EOA address
    const deployer = await EOA.getAddress();
    console.log("EOA is:", deployer);

    console.log("2. EOA to deploy BalancerBond contract");
    const gasPrice = ethers.utils.parseUnits(parsedData.gasPriceInGwei, "gwei");
    const gasLimit = 1000000;
    const BalancerBond = await ethers.getContractFactory("BalancerBond");
    console.log("You are signing the following transaction: BalancerBond.connect(EOA).deploy()");
    const balancerBond = await BalancerBond.connect(EOA).deploy(parsedData.olasAddress, parsedData.balancerVaultAddress,
        parsedData.balancerPoolId, { gasPrice, gasLimit });
    const result = await balancerBond.deployed();

    // Transaction details
    console.log("Contract deployment: BalancerBond");
    console.log("Contract address:", balancerBond.address);
    console.log("Transaction:", result.deployTransaction.hash);

    // Contract verification
    const execSync = require("child_process").execSync;
    execSync("npx hardhat verify --constructor-args scripts/deployment/verify_02_balancer_bond.js --network " + providerName + " " + balancerBond.address, { encoding: "utf-8" });
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
