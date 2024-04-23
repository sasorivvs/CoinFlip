// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

struct GameStorage {
    mapping(address => bool) isGame;
    mapping(address => bool) isTokenAllowed;
    address wrappedToken;
}

library LibStorage {
    bytes32 constant GAME_STORAGE_SLOT =
        bytes32(uint256(keccak256("vital.team.casino")) - 1);

    function gameStorage() internal pure returns (GameStorage storage gs) {
        bytes32 position = GAME_STORAGE_SLOT;
        assembly {
            gs.slot := position
        }
    }
}

contract WithStorage {
    function gs() internal pure returns (GameStorage storage) {
        return LibStorage.gameStorage();
    }
}
