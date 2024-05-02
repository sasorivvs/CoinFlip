const { network } = require("hardhat");
const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");
const { assert, expect } = require("chai");

describe("Random Number Consumer Unit Tests", async function () {
	// We define a fixture to reuse the same setup in every test.
	// We use loadFixture to run this setup once, snapshot that state,
	// and reset Hardhat Network to that snapshot in every test.
	async function deployRandomNumberConsumerFixture() {
		const [deployer, player] = await ethers.getSigners();

		/**
		 * @dev Read more at https://docs.chain.link/docs/chainlink-vrf/
		 */
		const BASE_FEE = "1000";
		const GAS_PRICE_LINK = "1000000000"; // 0.000000001 LINK per gas

		const chainId = network.config.chainId;

		const VRFCoordinatorV2MockFactory = await ethers.getContractFactory(
			"VRFCoordinatorV2Mock"
		);
		const VRFCoordinatorV2Mock = await VRFCoordinatorV2MockFactory.deploy(
			BASE_FEE,
			GAS_PRICE_LINK
		);

		const fundAmount = "1000000000000000000";
		const transaction = await VRFCoordinatorV2Mock.createSubscription();
		const transactionReceipt = await transaction.wait(1);
		const subscriptionId = ethers.BigNumber.from(
			transactionReceipt.events[0].topics[1]
		);
		await VRFCoordinatorV2Mock.fundSubscription(subscriptionId, fundAmount);

		const vrfCoordinatorAddress = VRFCoordinatorV2Mock.address;
		const keyHash =
			"0xd89b2bf150e3b9e13446986e571fb9cab24b13cea0a43ea20a6049a85cc807cc";

		const DECIMALS = "18";
		const INITIAL_PRICE = "2000";

		const mockV3AggregatorFactory = await ethers.getContractFactory(
			"MockV3Aggregator"
		);
		const mockV3Aggregator = await mockV3AggregatorFactory
			.connect(deployer)
			.deploy(DECIMALS, INITIAL_PRICE);

		const mockV3AggregatorAddress = mockV3Aggregator.address;

		const tokenAddress = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48";

		const wrappedETHaddress = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";

		const CoinFlipFactory = await ethers.getContractFactory("CoinFlip");
		const coinFlip = await CoinFlipFactory.connect(deployer).deploy(
			subscriptionId,
			vrfCoordinatorAddress,
			keyHash,
			mockV3AggregatorAddress,
			tokenAddress,
			wrappedETHaddress
		);

		await deployer.sendTransaction({
			to: coinFlip.address,
			value: ethers.utils.parseEther("1.0"),
		});

		await VRFCoordinatorV2Mock.addConsumer(
			subscriptionId,
			coinFlip.address
		);

		return { coinFlip, VRFCoordinatorV2Mock, deployer, player };
	}

	describe("#testOwnersFunctions", async function () {
		describe("success", async function () {
			it("Should successfully transfer Ownership", async function () {
				const { coinFlip, deployer, player } = await loadFixture(
					deployRandomNumberConsumerFixture
				);
				const notAnOwnerTX = coinFlip
					.connect(player)
					.transferOwnership(player.address);

				const ownerTX = coinFlip
					.connect(deployer)
					.transferOwnership(player.address);

				await expect(notAnOwnerTX).be.reverted;

				await expect(ownerTX)
					.to.emit(coinFlip, "Transfer_Ownership_Event")
					.withArgs(deployer.address, player.address);

				expect(await coinFlip.owner()).to.eq(player.address);
			});

			it("Should successfully change Subscription", async function () {
				const { coinFlip, deployer, player } = await loadFixture(
					deployRandomNumberConsumerFixture
				);
				const notAnOwnerTX = coinFlip
					.connect(player)
					.changeSubscription(2);

				const ownerTX = coinFlip
					.connect(deployer)
					.changeSubscription(2);

				await expect(notAnOwnerTX).be.reverted;

				await expect(ownerTX)
					.to.emit(coinFlip, "Subscrition_Change_Event")
					.withArgs(1, 2);

				expect(await coinFlip.s_subscriptionId()).to.eq(2);
			});

			it("Should successfully set bet Token", async function () {
				const { coinFlip, deployer, player } = await loadFixture(
					deployRandomNumberConsumerFixture
				);
				const notAnOwnerTX = coinFlip
					.connect(player)
					.setToken(
						"0x0000000000000000000000000000000000000001",
						true
					);

				const ownerTX = coinFlip
					.connect(deployer)
					.setToken(
						"0x0000000000000000000000000000000000000001",
						true
					);

				await expect(notAnOwnerTX).be.reverted;

				await expect(ownerTX)
					.to.emit(coinFlip, "Token_Set_Event")
					.withArgs(
						"0x0000000000000000000000000000000000000001",
						true
					);

				expect(
					await coinFlip.isTokenAllowed(
						"0x0000000000000000000000000000000000000001"
					)
				).to.eq(true);
			});

			it("Should successfully withdraw House Edge", async function () {
				const { coinFlip, deployer, player } = await loadFixture(
					deployRandomNumberConsumerFixture
				);
				withdrawAmount = 100;
				const notAnOwnerTX = coinFlip
					.connect(player)
					.withdrawHouseEdge(
						player.address,
						withdrawAmount,
						"0x0000000000000000000000000000000000000000"
					);

				const ownerTX = coinFlip
					.connect(deployer)
					.withdrawHouseEdge(
						player.address,
						withdrawAmount,
						"0x0000000000000000000000000000000000000000"
					);

				await expect(notAnOwnerTX).be.reverted;

				await expect(ownerTX)
					.to.emit(coinFlip, "Withdraw_HouseEdge_Event")
					.withArgs(
						player.address,
						withdrawAmount,
						"0x0000000000000000000000000000000000000000"
					);

				await expect(ownerTX).changeEtherBalance(
					player.address,
					withdrawAmount
				);
			});
		});
	});
});
