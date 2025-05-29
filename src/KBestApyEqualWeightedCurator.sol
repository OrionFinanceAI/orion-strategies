// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IMetaMorpho} from "@morpho-blue/interfaces/IMetaMorpho.sol";
import {Id} from "@morpho-blue/libraries/MorphoTypesLib.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/// @title KBestApyEqualWeightedCurator
/// @notice Filters top-k MetaMorpho vaults by APY and computes equal weighted allocation across them.
contract KBestApyEqualWeightedCurator {
    using EnumerableSet for EnumerableSet.Bytes32Set;

    IMetaMorpho[] public sources;
    uint256 public k;

    /// @param _sources Array of MetaMorpho vaults to choose from.
    /// @param _k Number of top vaults by APY to consider.
    constructor(IMetaMorpho[] memory _sources, uint256 _k) {
        require(_k > 0, "K must be > 0");
        require(_k <= _sources.length, "K cannot exceed number of sources");

        sources = _sources;
        k = _k;
    }

    /// @notice Compute equal weighted allocation from top k vaults by APY for a given market `id`.
    /// @param id Market Id to compute weight for.
    /// @return weight Weight scaled by 1e18 (i.e., 1e18 = 100%).
    function computeWeight(Id id) public view returns (uint256 weight) {
        uint256 n = sources.length;
        require(k <= n, "k exceeds sources length");

        // Collect APYs and their indices
        uint256[] memory apys = new uint256[](n);
        for (uint256 i = 0; i < n; i++) {
            apys[i] = sources[i].apy(); // assuming apy() returns uint256 scaled by 1e18
        }

        // Select indices of top k APYs (simple selection)
        uint256[] memory topKIndices = new uint256[](k);
        // Initialize with first k indices
        for (uint256 i = 0; i < k; i++) {
            topKIndices[i] = i;
        }

        // Find top k indices by APY
        for (uint256 i = k; i < n; i++) {
            // Find minimum APY among top k currently selected
            uint256 minIndex = 0;
            uint256 minApy = apys[topKIndices[0]];
            for (uint256 j = 1; j < k; j++) {
                if (apys[topKIndices[j]] < minApy) {
                    minApy = apys[topKIndices[j]];
                    minIndex = j;
                }
            }
            // If current apy is higher than min in top k, replace
            if (apys[i] > minApy) {
                topKIndices[minIndex] = i;
            }
        }

        // Calculate sum of allocations for the market `id` over top k vaults
        uint256 totalAllocation = 0;
        uint256 count = 0;

        for (uint256 i = 0; i < k; i++) {
            uint256 idx = topKIndices[i];
            (bool found, , , ) = sources[idx].strategyParams(id);
            if (found) {
                uint256 assets = sources[idx].vaultAssets(id);
                totalAllocation += assets;
                count++;
            }
        }

        if (count > 0) {
            // Equal weighting: average allocation across vaults that contain the market
            uint256 averageAllocation = totalAllocation / count;
            // Normalize by sum of total assets of the selected vaults to get a weight (scaled by 1e18)
            uint256 totalAssetsSelected = 0;
            for (uint256 i = 0; i < k; i++) {
                totalAssetsSelected += sources[topKIndices[i]].totalAssets();
            }
            if (totalAssetsSelected > 0) {
                weight = (averageAllocation * 1e18) / totalAssetsSelected;
            }
        }
    }
}
