// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "@chainlink/contracts/src/v0.8/vrf/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IVRFCoordinatorV2 is VRFCoordinatorV2Interface {
    function getFeeConfig()
        external
        view
        returns (
            uint32,
            uint32,
            uint32,
            uint32,
            uint32,
            uint24,
            uint24,
            uint24,
            uint24
        );
}

contract Common is ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public VRFFees;
    uint64 public s_subscriptionId;
    address public owner;
    address public wrappedToken;

    uint32 internal constant CALLBACK_GAS_LIMIT = 2500000;
    uint16 internal constant REQUEST_CONFIRMATIONS = 3;

    AggregatorV3Interface public immutable LINK_ETH_FEED;
    IVRFCoordinatorV2 public immutable COORDINATOR;
    bytes32 internal immutable KEY_HASH;

    constructor(
        uint64 subscriptionId,
        address link_eth_feed,
        address _vrf,
        bytes32 _keyHash,
        address _wrappedToken
    ) {
        COORDINATOR = IVRFCoordinatorV2(_vrf);
        LINK_ETH_FEED = AggregatorV3Interface(link_eth_feed);
        s_subscriptionId = subscriptionId;
        owner = msg.sender;
        KEY_HASH = _keyHash;
        wrappedToken = _wrappedToken;
    }

    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }

    error InvalidValue(uint256 required, uint256 sent);
    error TransferFailed();
    error RefundFailed();
    error NotOwner(address want, address have);
    error ZeroWager();
    error InvalidToken();

    /**
     * @dev function to transfer VRF fees acumulated in the contract
     * Can only be called by owner
     */
    function transferFees(address to) external nonReentrant onlyOwner {
        uint256 fee = VRFFees;
        VRFFees = 0;
        (bool success, ) = payable(to).call{value: fee}("");
        if (!success) {
            revert TransferFailed();
        }
    }

    /**
     * @dev calculates in form of native token the fee charged by chainlink VRF
     * @return fee amount of fee user has to pay
     */
    function getVRFFee(uint256 gasAmount) public view returns (uint256 fee) {
        (, int256 answer, , , ) = LINK_ETH_FEED.latestRoundData();
        (uint32 fulfillmentFlatFeeLinkPPMTier1, , , , , , , , ) = COORDINATOR
            .getFeeConfig();

        fee =
            (tx.gasprice * 18 * gasAmount) /
            10 +
            ((1e12 *
                uint256(fulfillmentFlatFeeLinkPPMTier1) *
                uint256(answer)) / 1e18);
    }

    /**
     * @dev function to transfer the player wager to game contract
     * , reverts if wager is zero
     * @param tokenAddress address of the token the wager is made on
     * @param wager total amount wagered
     * @param msgSender player address
     */

    function _transferWager(
        address tokenAddress,
        uint256 wager,
        uint256 gasAmount,
        address msgSender
    ) internal returns (uint256 VRFfee) {
        if (wager == 0) {
            revert ZeroWager();
        }
        VRFfee = getVRFFee(gasAmount);
        if (tokenAddress == address(0)) {
            if (msg.value < wager + VRFfee) {
                revert InvalidValue(wager + VRFfee, msg.value);
            }
            _refundExcessValue(msg.value - (VRFfee + wager));
        } else {
            if (msg.value < VRFfee) {
                revert InvalidValue(VRFfee, msg.value);
            }

            IERC20(tokenAddress).safeTransferFrom(
                msgSender,
                address(this),
                wager
            );

            _refundExcessValue(msg.value - VRFfee);
        }
        VRFFees += VRFfee;
    }

    /**
     * @dev returns to user the excess fee sent to pay for the VRF
     * @param refund amount to send back to user
     */
    function _refundExcessValue(uint256 refund) internal {
        if (refund == 0) {
            return;
        }
        (bool success, ) = payable(msg.sender).call{value: refund}("");
        if (!success) {
            revert RefundFailed();
        }
    }

    /**
     * @dev transfers payout from the game contract to the players
     * @param player address of the player to transfer the payout to
     * @param payout amount of payout to transfer
     * @param tokenAddress address of the token that payout will be transfered
     */
    function _transferPayout(
        address player,
        uint256 payout,
        address tokenAddress
    ) internal {
        if (tokenAddress == address(0)) {
            (bool success, ) = payable(player).call{value: payout}("");
            if (!success) {
                (bool _success, ) = wrappedToken.call{value: payout}(
                    abi.encodeWithSignature("deposit()")
                );
                if (!_success) {
                    revert TransferFailed();
                }
                IERC20(wrappedToken).safeTransfer(player, payout);
            }
        } else {
            IERC20(tokenAddress).safeTransfer(player, payout);
        }
    }

    /**
     * @dev transfers house edge from game contract
     * @param to address to transfer the house edge to
     * @param amount amount to transfer
     * @param tokenAddress address of token to transfer
     */
    function _transferHouseEdgePvP(
        address to,
        uint256 amount,
        address tokenAddress
    ) internal {
        if (tokenAddress == address(0)) {
            (bool success, ) = payable(to).call{value: amount}("");
            if (!success) {
                revert TransferFailed();
            }
        } else {
            IERC20(tokenAddress).safeTransfer(to, amount);
        }
    }

    /**
     * @dev function to transfer ownership
     * @param newOwner new owner address
     */
    function _transferOwnership(address newOwner) internal {
        owner = newOwner;
    }

    /**
     * @dev function to change Chainlink VRF subscription ID
     * @param _subscriptionId new Chainlink VRF subscription ID
     */
    function _changeSubscription(uint64 _subscriptionId) internal {
        s_subscriptionId = _subscriptionId;
    }

    /**
     * @dev function to send the request for randomness to chainlink
     * @param numWords number of random numbers required
     */
    function _requestRandomWords(
        uint32 numWords
    ) internal returns (uint256 requestId) {
        requestId = COORDINATOR.requestRandomWords(
            KEY_HASH,
            s_subscriptionId,
            REQUEST_CONFIRMATIONS,
            CALLBACK_GAS_LIMIT,
            numWords
        );
        return requestId;
    }
}
