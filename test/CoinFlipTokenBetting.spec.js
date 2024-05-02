const { network, ethers } = require("hardhat");
const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");
const { assert, expect } = require("chai");

describe("CoinFlip ERC20 betting Unit Tests", async function () {
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

		const tokenFactory = await ethers.getContractFactory("TestToken");
		const token = await tokenFactory
			.connect(deployer)
			.deploy([deployer.address, player.address]);

		const tokenAddress = token.address;

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

		await token.connect(player).approve(coinFlip.address, 10000);
		await token.mint(coinFlip.address, 10000);

		return { coinFlip, VRFCoordinatorV2Mock, token, deployer, player };
	}

	describe("#requestRandomWords", async function () {
		describe("success", async function () {
			it("Should successfully request a random number", async function () {
				const {
					coinFlip,
					VRFCoordinatorV2Mock,
					token,
					deployer,
					player,
				} = await loadFixture(deployRandomNumberConsumerFixture);

				const wagerAboveLimitTX = coinFlip
					.connect(player)
					.CoinFlip_Play(1000, token.address, true, 1, 10, 10, {
						value: ethers.utils.parseEther("1"),
					});

				await expect(wagerAboveLimitTX).be.revertedWithCustomError(
					coinFlip,
					"WagerAboveLimit"
				);

				const playTX = await coinFlip
					.connect(player)
					.CoinFlip_Play(1, token.address, true, 1, 10, 10, {
						value: ethers.utils.parseEther("1"),
					});

				await expect(playTX).to.emit(
					VRFCoordinatorV2Mock,
					"RandomWordsRequested"
				);

				await expect(playTX)
					.to.emit(coinFlip, "CoinFlip_Play_Event")
					.withArgs(
						player.address,
						1,
						token.address,
						true,
						1,
						10,
						10,
						await coinFlip.VRFFees()
					);
			});
			it("Should successfully take the bet, save the VRFFee information", async function () {
				const { coinFlip, deployer, player, token } = await loadFixture(
					deployRandomNumberConsumerFixture
				);

				const balanceBeforeTx = await ethers.provider.getBalance(
					coinFlip.address
				);
				const tokenBalanceBeforeTx = await token.balanceOf(
					coinFlip.address
				);
				const wager = 1;
				await coinFlip
					.connect(player)
					.CoinFlip_Play(wager, token.address, true, 1, 10, 10, {
						value: ethers.utils.parseEther("1"),
					});
				const balanceAfterTx = await ethers.provider.getBalance(
					coinFlip.address
				);

				const tokenBalanceAfterTx = await token.balanceOf(
					coinFlip.address
				);
				const VRFFees = await coinFlip.VRFFees();
				expect(VRFFees).gt(ethers.constants.Zero);
				expect(balanceAfterTx.sub(balanceBeforeTx).sub(VRFFees)).to.eq(
					0
				);
				expect(tokenBalanceAfterTx.sub(tokenBalanceBeforeTx)).to.eq(
					wager
				);
			});

			it("Should correctly calculate the award and make the payment", async function () {
				const { player, token, coinFlip, VRFCoordinatorV2Mock } =
					await loadFixture(deployRandomNumberConsumerFixture);
				const wager = 100;
				const numGames = 5;
				const playTX = await coinFlip
					.connect(player)
					.CoinFlip_Play(
						wager,
						token.address,
						true,
						numGames,
						10000,
						10000,
						{
							value: ethers.utils.parseEther("1"),
						}
					);
				const state = await coinFlip.CoinFlip_GetState(player.address);
				const requestId = state.requestID;

				//simulate callback from the oracle network
				const payoutTX = await VRFCoordinatorV2Mock.fulfillRandomWords(
					requestId,
					coinFlip.address
				);
				const events = await coinFlip.queryFilter(
					"CoinFlip_Outcome_Event"
				);
				const outcomes = events[0].args.coinOutcomes;
				let count = outcomes.reduce(function (sum, elem) {
					return sum + elem;
				}, 0);

				const payout = (count * 198 * wager) / 100;
				await expect(payoutTX).to.changeTokenBalance(
					token,
					player.address,
					payout
				);

				await expect(payoutTX).to.changeTokenBalance(
					token,
					coinFlip.address,
					-payout
				);
			});

			it("Should stop games when stopGain is reached", async function () {
				const { player, token, coinFlip, VRFCoordinatorV2Mock } =
					await loadFixture(deployRandomNumberConsumerFixture);
				const wager = 100;
				const stopGain = 150;
				const stopLoss = 300;
				const numGames = 5;
				const playTX = await coinFlip
					.connect(player)
					.CoinFlip_Play(
						wager,
						token.address,
						true,
						numGames,
						stopGain,
						stopLoss,
						{
							value: ethers.utils.parseEther("1"),
						}
					);
				const state = await coinFlip.CoinFlip_GetState(player.address);
				const requestId = state.requestID;

				//simulate callback from the oracle network
				const payoutTX =
					await VRFCoordinatorV2Mock.fulfillRandomWordsWithOverride(
						requestId,
						coinFlip.address,
						[1, 1, 1, 1, 1]
					);
				const events = await coinFlip.queryFilter(
					"CoinFlip_Outcome_Event"
				);
				const outcomes = events[0].args.numGames;

				// 2*wager*0.98 > stopGain > 1*wager*0.98
				expect(events[0].args.numGames).to.eq(2);

				const gamesPlayed = events[0].args.numGames;
				await expect(payoutTX).changeTokenBalance(
					token,
					player.address,
					(numGames - gamesPlayed) * wager +
						(gamesPlayed * 198 * wager) / 100
				);
			});

			it("Should stop games when stopLoss is reached", async function () {
				const { player, coinFlip, token, VRFCoordinatorV2Mock } =
					await loadFixture(deployRandomNumberConsumerFixture);
				const wager = 100;
				const stopGain = 150;
				const stopLoss = 201;
				const numGames = 5;
				const playTX = await coinFlip
					.connect(player)
					.CoinFlip_Play(
						wager,
						token.address,
						true,
						numGames,
						stopGain,
						stopLoss,
						{
							value: ethers.utils.parseEther("1"),
						}
					);
				const state = await coinFlip.CoinFlip_GetState(player.address);
				const requestId = state.requestID;

				//simulate callback from the oracle network
				const payoutTX =
					await VRFCoordinatorV2Mock.fulfillRandomWordsWithOverride(
						requestId,
						coinFlip.address,
						[0, 0, 0, 0, 0]
					);
				const events = await coinFlip.queryFilter(
					"CoinFlip_Outcome_Event"
				);
				const outcomes = events[0].args.numGames;

				// 3 * wager > stopLoss > 2 * wager
				expect(events[0].args.numGames).to.eq(3);

				const gamesPlayed = events[0].args.numGames;
				await expect(payoutTX).changeTokenBalance(
					token,
					player.address,
					(numGames - gamesPlayed) * wager
				);
			});

			it("Should work properly CoinFlip_Refund()", async function () {
				const { player, coinFlip, token } = await loadFixture(
					deployRandomNumberConsumerFixture
				);
				const wager = 100;
				const stopGain = 150;
				const stopLoss = 201;
				const numGames = 5;
				const playTX = await coinFlip
					.connect(player)
					.CoinFlip_Play(
						wager,
						token.address,
						true,
						numGames,
						stopGain,
						stopLoss,
						{
							value: ethers.utils.parseEther("1"),
						}
					);
				const firstRefundTx = coinFlip
					.connect(player)
					.CoinFlip_Refund();

				await expect(firstRefundTx).be.revertedWithCustomError(
					coinFlip,
					"BlockNumberTooLow"
				);

				for (let i = 0; i < 100; i++) {
					await network.provider.send("evm_mine");
				}

				const secondRefundTx = coinFlip
					.connect(player)
					.CoinFlip_Refund();
				await expect(secondRefundTx).changeTokenBalance(
					token,
					player.address,
					wager * numGames
				);
				await expect(secondRefundTx).changeTokenBalance(
					token,
					coinFlip.address,
					-wager * numGames
				);
				await expect(secondRefundTx)
					.to.emit(coinFlip, "CoinFlip_Refund_Event")
					.withArgs(player.address, numGames * wager, token.address);
			});
		});
	});
});
