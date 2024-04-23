// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import {WithStorage} from "./libraries/LibStorage.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract Bankroll is WithStorage {
    using SafeERC20 for IERC20;
    address public owner;

    /**
     * @dev event emitted when game is Added or Removed
     * @param gameAddress address of game state that changed
     * @param isValid new state of game address
     */

    event BankRoll_Game_State_Changed(address gameAddress, bool isValid);
    /**
     * @dev event emitted when token state is changed
     * @param tokenAddress address of token that changed state
     * @param isValid new state of token address
     */
    event Bankroll_Token_State_Changed(address tokenAddress, bool isValid);

    /**
     * @dev event emitted when owner is changed
     * @param newOwner address of owner that changed
     */
    event BankRoll_Owner_Changed(address newOwner);

    error InvalidGameAddress();
    error TransferFailed();

    constructor(address _owner) {
        owner = _owner;
    }

    modifier onlyOwner() {
        require(msg.sender == getOwner());
        _;
    }

    /**
     * @dev remove funds from the bankroll
     */
    function withdrawFunds(
        address tokenAddress,
        address to,
        uint256 amount
    ) external onlyOwner {
        IERC20(tokenAddress).safeTransfer(to, amount);
    }

    function transferPayout(
        address player,
        uint256 payout,
        address token
    ) external {
        if (gs().isGame[msg.sender] == false) {
            revert InvalidGameAddress();
        }
        if (token != address(0)) {
            IERC20(token).safeTransfer(player, payout);
        } else {
            (bool success, ) = payable(player).call{value: payout, gas: 2400}(
                ""
            );
            if (!success) {
                (bool _success, ) = gs().wrappedToken.call{value: payout}(
                    abi.encodeWithSignature("deposit()")
                );
                if (!_success) {
                    revert();
                }
                IERC20(gs().wrappedToken).safeTransfer(player, payout);
            }
        }
    }

    /**
     * @dev remove funds from the bankroll
     */
    function withdrawNativeFunds(
        address to,
        uint256 amount
    ) external onlyOwner {
        (bool success, ) = payable(to).call{value: amount}("");
        if (!success) {
            revert TransferFailed();
        }
    }

    function getIsGame(address game) external view returns (bool) {
        return gs().isGame[game];
    }

    function getIsValidWager(
        address game,
        address tokenAddress
    ) external view returns (bool) {
        return (gs().isGame[game] && gs().isTokenAllowed[tokenAddress]);
    }

    function setGame(address game, bool isValid) external onlyOwner {
        gs().isGame[game] = isValid;
        emit BankRoll_Game_State_Changed(game, isValid);
    }

    function setTokenAddress(
        address tokenAddress,
        bool isValid
    ) external onlyOwner {
        gs().isTokenAllowed[tokenAddress] = isValid;
        emit Bankroll_Token_State_Changed(tokenAddress, isValid);
    }

    function setWrappedAddress(address wrapped) external onlyOwner {
        gs().wrappedToken = wrapped;
    }

    function getWrappedAddress() external view returns (address) {
        return gs().wrappedToken;
    }

    function changeOwner(address _owner) external onlyOwner {
        owner = _owner;
        emit BankRoll_Owner_Changed(owner);
    }

    function getOwner() public view returns (address) {
        return owner;
    }
}
