// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { IOrionTransparentVault } from "orion-protocol/contracts/interfaces/IOrionTransparentVault.sol";
import { IOrionConfig } from "orion-protocol/contracts/interfaces/IOrionConfig.sol";
import { ErrorsLib } from "./libraries/ErrorsLib.sol";

/// @title KBestTvlWeightedAverage
contract KBestTvlWeightedAverage is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable {
    /// @notice The curated vault to allocate to
    IOrionTransparentVault public curatedVault;

    /// @notice The universe of assets to pick from
    address[] public universe;

    /// @notice The number of assets to pick
    uint8 public K;

    function initialize(
        address initialOwner,
        address _curatedVault,
        address[] calldata _universe,
        uint8 _K
    ) external initializer {
        if (_curatedVault == address(0)) revert ErrorsLib.ZeroAddress();
        if (_K > 0 && _K <= _universe.length) revert ErrorsLib.InvalidK();

        __Ownable_init(initialOwner);
        __Ownable2Step_init();
        __UUPSUpgradeable_init();

        curatedVault = IOrionTransparentVault(_curatedVault);
        universe = _universe;
        K = _K;
    }

    // solhint-disable-next-line no-empty-blocks
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {
        // Only the owner can upgrade the contract
    }

    function rebalance() external onlyOwner {
        uint8 N = uint8(universe.length);

        uint256[] memory tvls = _getTVLs(N);

        (address[] memory tokens, uint256[] memory TVLs) = _getKBest(tvls, N);

        IOrionTransparentVault.Position[] memory intent = _buildIntent(tokens, TVLs);

        curatedVault.submitIntent(intent);
    }

    function _getTVLs(uint8 N) internal view returns (uint256[] memory tvls) {
        tvls = new uint256[](N);
        for (uint8 i = 0; i < N; ++i) {
            tvls[i] = 100; // TODO: fetch actual TVLs
        }
    }

    function _getKBest(
        uint256[] memory tvls,
        uint8 N
    ) internal view returns (address[] memory tokens, uint256[] memory TVLs) {
        tokens = new address[](K);
        TVLs = new uint256[](K);
        bool[] memory used = new bool[](N);
        for (uint8 k = 0; k < K; ++k) {
            uint256 maxTVL = 0;
            uint256 maxIndex = 0;
            for (uint8 i = 0; i < N; ++i) {
                if (!used[i] && tvls[i] > maxTVL) {
                    maxTVL = tvls[i];
                    maxIndex = i;
                }
            }
            used[maxIndex] = true;
            tokens[k] = universe[maxIndex];
            TVLs[k] = tvls[maxIndex];
        }
    }

    function _buildIntent(
        address[] memory tokens,
        uint256[] memory TVLs
    ) internal view returns (IOrionTransparentVault.Position[] memory intent) {
        uint256 totalTVL = 0;
        for (uint8 i = 0; i < K; ++i) {
            totalTVL += TVLs[i];
        }

        uint32 intentScale = uint32(10 ** curatedVault.config().curatorIntentDecimals());
        intent = new IOrionTransparentVault.Position[](K);

        uint32 sumWeights = 0;
        for (uint8 i = 0; i < K; ++i) {
            uint32 weight = uint32((TVLs[i] * intentScale) / totalTVL);
            intent[i] = IOrionTransparentVault.Position({ token: tokens[i], value: uint32(TVLs[i]) });
            sumWeights += weight;
        }

        if (sumWeights != intentScale) {
            uint32 diff = intentScale - sumWeights;
            intent[K - 1].value -= diff;
        }
    }

    /// @notice Owner can update universe or K
    function updateParameters(address[] calldata _universe, uint8 K_new) external onlyOwner {
        // TODO: check that the new universe entries are orion whitelisted.
        if (K_new > 0 && K_new <= _universe.length) revert ErrorsLib.InvalidK();
        universe = _universe;
        K = K_new;
    }
}
