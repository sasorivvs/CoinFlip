require("@nomicfoundation/hardhat-toolbox");

const COMPILER_SETTINGS = {
	optimizer: {
		enabled: true,
		runs: 1000000,
	},
	metadata: {
		bytecodeHash: "none",
	},
};

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
	solidity: {
		compilers: [
			{
				version: "0.8.20",
				COMPILER_SETTINGS,
			},
			{
				version: "0.8.7",
				COMPILER_SETTINGS,
			},
			{
				version: "0.6.6",
				COMPILER_SETTINGS,
			},
			{
				version: "0.4.24",
				COMPILER_SETTINGS,
			},
		],
	},

	defaultNetwork: "hardhat",

	paths: {
		sources: "./contracts",
		tests: "./test",
		cache: "./build/cache",
		artifacts: "./build/artifacts",
	},
	mocha: {
		timeout: 300000, // 300 seconds max for running tests
	},
};
