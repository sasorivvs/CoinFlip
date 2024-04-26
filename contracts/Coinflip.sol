// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "./Common.sol";

contract CoinFlip is Common {
    using SafeERC20 for IERC20;

    mapping(address => CoinFlipGame) coinFlipGames;
    mapping(uint256 => address) coinIDs;
    mapping(address => bool) isTokenAllowed;

    constructor(
        uint64 subscriptionID,
        address _vrf,
        bytes32 _keyHash,
        address link_eth_feed,
        address tokenAllowed,
        address wrappedToken
    ) Common(subscriptionID, link_eth_feed, _vrf, _keyHash, wrappedToken) {
        isTokenAllowed[tokenAllowed] = true;
    }

    struct CoinFlipGame {
        uint256 wager;
        uint256 stopGain;
        uint256 stopLoss;
        uint256 requestID;
        address tokenAddress;
        uint64 blockNumber;
        uint32 numBets;
        bool isHeads;
    }

    /**
     * @dev event emitted at the start of the game
     * @param playerAddress address of the player that made the bet
     * @param wager wagered amount
     * @param tokenAddress address of token the wager was made, 0 address is considered the native coin
     * @param isHeads player bet on which side the coin will land  1-> Heads, 0 ->Tails
     * @param numBets number of bets the player intends to make
     * @param stopGain gain value at which the betting stop if a gain is reached
     * @param stopLoss loss value at which the betting stop if a loss is reached
     */
    event CoinFlip_Play_Event(
        address indexed playerAddress,
        uint256 wager,
        address tokenAddress,
        bool isHeads,
        uint32 numBets,
        uint256 stopGain,
        uint256 stopLoss,
        uint256 VRFFee
    );

    /**
     * @dev event emitted by the VRF callback with the bet results
     * @param playerAddress address of the player that made the bet
     * @param wager wager amount
     * @param payout total payout transfered to the player
     * @param tokenAddress address of token the wager was made and payout, 0 address is considered the native coin
     * @param coinOutcomes results of coinFlip, 1-> Heads, 0 ->Tails
     * @param payouts individual payouts for each bet
     * @param numGames number of games performed
     */
    event CoinFlip_Outcome_Event(
        address indexed playerAddress,
        uint256 wager,
        uint256 payout,
        address tokenAddress,
        uint8[] coinOutcomes,
        uint256[] payouts,
        uint32 numGames
    );

    /**
     * @dev event emitted when a refund is done in coin flip
     * @param player address of the player receiving the refund
     * @param wager amount of wager that was refunded
     * @param tokenAddress address of token the refund was made in
     */
    event CoinFlip_Refund_Event(
        address indexed player,
        uint256 wager,
        address tokenAddress
    );

    /**
     * @dev event emitted when a transfer of ownership is done
     * @param prevOwner address of the previous owner
     * @param newOwner address of the new owner
     */
    event Transfer_Ownership_Event(address prevOwner, address newOwner);

    /**
     * @dev event emitted when the contract was funded with native currency
     * @param sender refill address
     * @param amount refill amount
     */
    event Received(address sender, uint amount);

    error WagerAboveLimit(uint256 wager, uint256 maxWager);
    error AwaitingVRF(uint256 requestID);
    error InvalidNumBets(uint256 maxNumBets);
    error NotAwaitingVRF();
    error BlockNumberTooLow(uint256 have, uint256 want);
    error OnlyCoordinatorCanFulfill(address have, address want);

    receive() external payable {
        emit Received(msg.sender, msg.value);
    }

    /**
     * @dev Function to play Coin Flip, takes the user wager saves bet parameters and makes a request to the VRF
     * @param wager wager amount
     * @param tokenAddress address of token to bet, 0 address is considered the native coin
     * @param numBets number of bets to make, and amount of random numbers to request
     * @param stopGain treshold value at which the bets stop if a certain profit is obtained
     * @param stopLoss treshold value at which the bets stop if a certain loss is obtained
     * @param isHeads if bet selected heads or Tails
     */
    function CoinFlip_Play(
        uint256 wager,
        address tokenAddress,
        bool isHeads,
        uint32 numBets,
        uint256 stopGain,
        uint256 stopLoss
    ) external payable nonReentrant {
        if (coinFlipGames[msg.sender].requestID != 0) {
            revert AwaitingVRF(coinFlipGames[msg.sender].requestID);
        }
        if (!(numBets > 0 && numBets <= 100)) {
            revert InvalidNumBets(100);
        }

        _kellyWager(wager, tokenAddress);
        uint256 fee = _transferWager(
            tokenAddress,
            wager * numBets,
            700000,
            msg.sender
        );

        uint256 id = _requestRandomWords(numBets);

        coinFlipGames[msg.sender] = CoinFlipGame(
            wager,
            stopGain,
            stopLoss,
            id,
            tokenAddress,
            uint64(block.number),
            numBets,
            isHeads
        );
        coinIDs[id] = msg.sender;

        emit CoinFlip_Play_Event(
            msg.sender,
            wager,
            tokenAddress,
            isHeads,
            numBets,
            stopGain,
            stopLoss,
            fee
        );
    }

    /**
     * @dev Function to refund user in case of VRF request failling
     */
    function CoinFlip_Refund() external nonReentrant {
        CoinFlipGame storage game = coinFlipGames[msg.sender];
        if (game.requestID == 0) {
            revert NotAwaitingVRF();
        }
        if (game.blockNumber + 100 > block.number) {
            revert BlockNumberTooLow(block.number, game.blockNumber + 100);
        }

        uint256 wager = game.wager * game.numBets;
        address tokenAddress = game.tokenAddress;

        delete (coinIDs[game.requestID]);
        delete (coinFlipGames[msg.sender]);

        if (tokenAddress == address(0)) {
            (bool success, ) = payable(msg.sender).call{value: wager}("");
            if (!success) {
                revert TransferFailed();
            }
        } else {
            IERC20(tokenAddress).safeTransfer(msg.sender, wager);
        }
        emit CoinFlip_Refund_Event(msg.sender, wager, tokenAddress);
    }

    /**
     * @dev transfers house edge from game contract
     * Can only be called by owner
     * @param to address to transfer the house edge to
     * @param amount amount to transfer
     * @param tokenAddress address of token to transfer
     */
    function withdrawHouseEdge(
        address to,
        uint amount,
        address tokenAddress
    ) external onlyOwner {
        _transferHouseEdgePvP(to, amount, tokenAddress);
    }

    /**
     * @dev function to transfer ownership
     * Can only be called by owner
     * @param newOwner new owner address
     */
    function transferOwnership(address newOwner) external onlyOwner {
        emit Transfer_Ownership_Event(owner, newOwner);
        _transferOwnership(newOwner);
    }

    /**
     * @dev function to change Chainlink VRF subscription ID
     * Can only be called by owner
     * @param _subscriptionId new Chainlink VRF subscription ID
     */
    function changeSubscription(uint64 _subscriptionId) external onlyOwner {
        _changeSubscription(_subscriptionId);
    }

    /**
     * @dev function to get current request player is await from VRF, returns 0 if none
     * @param player address of the player to get the state
     */
    function CoinFlip_GetState(
        address player
    ) external view returns (CoinFlipGame memory) {
        return (coinFlipGames[player]);
    }

    /**
     * @dev function called by Chainlink VRF with random numbers
     * @param requestId id provided when the request was made
     * @param randomWords array of random numbers
     */
    function rawFulfillRandomWords(
        uint256 requestId,
        uint256[] memory randomWords
    ) external {
        if (msg.sender != address(COORDINATOR)) {
            revert OnlyCoordinatorCanFulfill(msg.sender, address(COORDINATOR));
        }
        fulfillRandomWords(requestId, randomWords);
    }

    function fulfillRandomWords(
        uint256 requestId,
        uint256[] memory randomWords
    ) internal {
        address playerAddress = coinIDs[requestId];
        if (playerAddress == address(0)) revert();
        CoinFlipGame storage game = coinFlipGames[playerAddress];
        if (block.number > game.blockNumber + 100) revert();
        int256 totalValue;
        uint256 payout;
        uint32 i;
        uint8[] memory coinFlip = new uint8[](game.numBets);
        uint256[] memory payouts = new uint256[](game.numBets);

        address tokenAddress = game.tokenAddress;

        for (i = 0; i < game.numBets; i++) {
            if (totalValue >= int256(game.stopGain)) {
                break;
            }
            if (totalValue <= -int256(game.stopLoss)) {
                break;
            }

            coinFlip[i] = uint8(randomWords[i] % 2);

            if (coinFlip[i] == 1 && game.isHeads == true) {
                totalValue += int256((game.wager * 9800) / 10000);
                payout += (game.wager * 19800) / 10000;
                payouts[i] = (game.wager * 19800) / 10000;
                continue;
            }
            if (coinFlip[i] == 0 && game.isHeads == false) {
                totalValue += int256((game.wager * 9800) / 10000);
                payout += (game.wager * 19800) / 10000;
                payouts[i] = (game.wager * 19800) / 10000;
                continue;
            }

            totalValue -= int256(game.wager);
        }

        payout += (game.numBets - i) * game.wager;

        emit CoinFlip_Outcome_Event(
            playerAddress,
            game.wager,
            payout,
            tokenAddress,
            coinFlip,
            payouts,
            i
        );
        delete (coinIDs[requestId]);
        delete (coinFlipGames[playerAddress]);
        if (payout != 0) {
            _transferPayout(playerAddress, payout, tokenAddress);
        }
    }

    /**
     * @dev calculates the maximum wager allowed based on the bankroll size
     */
    function _kellyWager(uint256 wager, address tokenAddress) internal view {
        uint256 balance;
        if (tokenAddress == address(0)) {
            balance = address(this).balance;
        } else {
            if (isTokenAllowed[tokenAddress] == false) {
                revert InvalidToken();
            }
            balance = IERC20(tokenAddress).balanceOf(address(this));
        }
        uint256 maxWager = (balance * 5) / 100;
        if (wager > maxWager) {
            revert WagerAboveLimit(wager, maxWager);
        }
    }
}
