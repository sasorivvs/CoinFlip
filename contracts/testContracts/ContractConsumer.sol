// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

interface ICoinFlip {
    function CoinFlip_Play(
        uint256,
        address,
        bool,
        uint32,
        uint256,
        uint256
    ) external payable;
}

contract Consumer {
    ICoinFlip public coinflip;
    address public allowedDepositor;
    bool public isRefund = true;

    constructor(address _coinflip) {
        coinflip = ICoinFlip(_coinflip);
        allowedDepositor = msg.sender;
    }

    error InvalidDepositor();

    receive() external payable {
        if (isRefund) {
            isRefund = false;
        } else revert InvalidDepositor();
    }

    function placeBet(
        uint256 wager,
        address tokenAddress,
        bool isHeads,
        uint32 numBets,
        uint256 stopGain,
        uint256 stopLoss
    ) public payable {
        coinflip.CoinFlip_Play{value: msg.value}(
            wager,
            tokenAddress,
            isHeads,
            numBets,
            stopGain,
            stopLoss
        );
    }
}
