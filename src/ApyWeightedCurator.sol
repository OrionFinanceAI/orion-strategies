// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IMetaMorpho} from "@morpho-blue/interfaces/IMetaMorpho.sol";
import {Id, MarketParams} from "@morpho-blue/libraries/MorphoTypesLib.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/// @title ApyWeightedCurator
/// @notice Sets weights as the APY-weighted average of referenced MetaMorpho vaults.
contract ApyWeightedCurator is BaseCurator {
    using EnumerableSet for EnumerableSet.Bytes32Set;

    IMetaMorpho[] public sources;
    mapping(bytes32 => bool) private isKnown;

    constructor(IMetaMorpho[] memory _sources) {
        sources = _sources;
        _updateQueuesFromSources();
    }

    /// @notice Computes an APY-weighted average across all referenced MetaMorpho vaults.
    function computeWeight(Id id) public view override returns (uint256 weight) {
        uint256 totalApySum = 0;
        uint256 idApySum = 0;

        // Collect all unique market IDs once for total APY calculation
        EnumerableSet.Bytes32Set memory marketSet;

        for (uint256 i = 0; i < sources.length; ++i) {
            IMetaMorpho vault = sources[i];

            uint256 supplyLen = vault.supplyQueueLength();
            for (uint256 j = 0; j < supplyLen; ++j) {
                Id marketId = vault.supplyQueue(j);
                marketSet.add(_hash(marketId));
            }

            uint256 withdrawLen = vault.withdrawQueueLength();
            for (uint256 j = 0; j < withdrawLen; ++j) {
                Id marketId = vault.withdrawQueue(j);
                marketSet.add(_hash(marketId));
            }
        }

        // Sum APYs over all unique markets in all sources
        for (uint256 i = 0; i < marketSet.length(); ++i) {
            Id marketId = _fromHash(marketSet.at(i));

            for (uint256 s = 0; s < sources.length; ++s) {
                (bool found, uint256 apy, , ) = sources[s].strategyParams(marketId);
                if (found) {
                    totalApySum += apy;
                }
            }
        }

        // Sum APYs for the specific market `id`
        for (uint256 s = 0; s < sources.length; ++s) {
            (bool found, uint256 apy, , ) = sources[s].strategyParams(id);
            if (found) {
                idApySum += apy;
            }
        }

        if (totalApySum > 0) {
            weight = (idApySum * 1e18) / totalApySum; // normalized weight [0..1e18]
        }
    }

    /// @dev Computes the union of all market IDs from the source vaults.
    function _updateQueuesFromSources() internal {
        EnumerableSet.Bytes32Set memory marketSet;

        for (uint256 i = 0; i < sources.length; ++i) {
            IMetaMorpho vault = sources[i];

            uint256 supplyLen = vault.supplyQueueLength();
            for (uint256 j = 0; j < supplyLen; ++j) {
                Id market = vault.supplyQueue(j);
                marketSet.add(_hash(market));
            }

            uint256 withdrawLen = vault.withdrawQueueLength();
            for (uint256 j = 0; j < withdrawLen; ++j) {
                Id market = vault.withdrawQueue(j);
                marketSet.add(_hash(market));
            }
        }

        Id[] memory unionMarkets = new Id[](marketSet.length());
        for (uint256 i = 0; i < marketSet.length(); ++i) {
            unionMarkets[i] = _fromHash(marketSet.at(i));
        }

        setSupplyQueue(unionMarkets);

        uint256[] memory indices = new uint256[](unionMarkets.length);
        for (uint256 i = 0; i < indices.length; ++i) {
            indices[i] = i;
        }
        updateWithdrawQueue(indices);
    }

    function _hash(Id id) internal pure returns (bytes32) {
        return keccak256(abi.encode(id));
    }

    function _fromHash(bytes32 hash) internal pure returns (Id memory id) {
        assembly {
            mstore(id, shr(96, hash)) // morpho
            mstore(add(id, 0x20), shr(96, shl(96, hash))) // loanToken
            mstore(add(id, 0x40), shr(96, shl(192, hash))) // collateralToken
            mstore(add(id, 0x60), shl(224, hash)) // oracle
        }
    }
}
