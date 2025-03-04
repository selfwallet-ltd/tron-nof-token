const NOF = artifacts.require("NOFToken");

module.exports = function(deployer) {
  deployer.deploy(NOF, {
    consume_user_resource_percent: 0,  
    originEnergyLimit: 10000000,     
    fee_limit: 1000000000,           
    userFeePercentage: 0          
  });
};