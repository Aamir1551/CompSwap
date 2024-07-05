const ComputationMarket = artifacts.require("ComputationMarket");
const CompToken = artifacts.require("COMPToken");

module.exports = async function (deployer) {
    await deployer.deploy(CompToken, 10);
    const compTokenInstance = await CompToken.deployed();
    await deployer.deploy(ComputationMarket, compTokenInstance.address);
};