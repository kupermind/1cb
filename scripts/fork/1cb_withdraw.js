/*global process*/

const { ethers } = require("ethers");

async function main() {
    // To run anvil fork with auto-impersonate, use the following command:
    // anvil -f node_URL_chain_id_1 --fork-block-number 18676330 --gas-price 20000000000 --gas-limit 1600000000 --auto-impersonate

    // export PRIVATE_KEY = one_of_anvil_generated_private_keys

    const URL = "http://127.0.0.1:8545";
    const provider = new ethers.providers.JsonRpcProvider(URL);
    await provider.getBlockNumber().then((result) => {
        console.log("Current fork block number: " + result);
    });

    const fs = require("fs");

    // Get all the necessary contract addresses
    const timelockAddress = "0x3C1fF68f5aa342D296d4DEe4Bb1cACCA912D95fE";
    const depositoryAddress = "0xfF8697d8d2998d6AA2e09B405795C6F4BEeB0C81";
    const olasAddress = "0x0001A500A6B18995B03f44bb040A5fFc28E45CB0";
    const oneClickBondAddress = "0x751170F1e39F80aBF2C6CE0DC57623F4D87D473F";

    // Timelock address is used as an impersonated signer
    const signer = provider.getSigner(timelockAddress);

    let privateKey = process.env.PRIVATE_KEY;
    let wallet = new ethers.Wallet(privateKey, provider);
    await wallet.sendTransaction({to: timelockAddress, value: ethers.utils.parseEther("1")});

    const depositoryJSON = "abis/Depository.json";
    let contractFromJSON = fs.readFileSync(depositoryJSON, "utf8");
    let parsedFile = JSON.parse(contractFromJSON);
    let abi = parsedFile["abi"];

    // Depository contract instance
    const depository = new ethers.Contract(depositoryAddress, abi, signer);
    console.log("Depository address:", depository.address);

    const olasJSON = "abis/OLAS.json";
    contractFromJSON = fs.readFileSync(olasJSON, "utf8");
    parsedFile = JSON.parse(contractFromJSON);
    abi = parsedFile["abi"];

    // OLAS instance
    const olas = new ethers.Contract(olasAddress, abi, signer);
    console.log("OLAS address:", olas.address);

    // Deploy the 1CB contract
    const oneClickBondJSON = "artifacts/contracts/OneClickBond.sol/OneClickBond.json";
    contractFromJSON = fs.readFileSync(oneClickBondJSON, "utf8");
    parsedFile = JSON.parse(contractFromJSON);
    abi = parsedFile["abi"];

    // OneClickBond instance
    const oneClickBond = new ethers.Contract(oneClickBondAddress, abi, signer);

    // Get OLAs balance before withdraw
    const balanceBefore = await olas.balanceOf(timelockAddress);
    console.log("OLAS balance before", balanceBefore.toString());

    // Get matured bonds
    const bonds = await depository.getBonds(oneClickBond.address, true);
    //console.log(bonds);

    // Redeem bonds and withdraw OLAS
    await oneClickBond.connect(signer).withdraw(bonds.bondIds);

    // Get OLAS balance after the withdraw
    const balanceAfter = await olas.balanceOf(timelockAddress);
    console.log("OLAS balance after", balanceAfter.toString());

    const balanceDiff = balanceAfter.sub(balanceBefore);
    console.log("OLAS difference after withdraw:", balanceDiff.toString());
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
