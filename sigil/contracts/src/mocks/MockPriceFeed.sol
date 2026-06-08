// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AggregatorV3Interface} from "@chainlink/shared/interfaces/AggregatorV3Interface.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title MockPriceFeed
/// @notice Chainlink AggregatorV3Interface-compatible mock for demo and testing.
///         Start: ETH at $3,800. Demo trigger: dropPrice(340000000000) → fires the exit watcher.
contract MockPriceFeed is AggregatorV3Interface, Ownable {
    int256 private _price;
    uint8 private _decimals;
    string private _description;
    uint80 private _roundId;
    uint256 private _updatedAt;

    event PriceUpdated(int256 oldPrice, int256 newPrice, uint80 roundId);

    error PriceNotLower();

    constructor(
        int256 initialPrice,
        uint8 feedDecimals,
        string memory feedDescription,
        address _owner
    ) Ownable(_owner) {
        _price = initialPrice;
        _decimals = feedDecimals;
        _description = feedDescription;
        _roundId = 1;
        _updatedAt = block.timestamp;
    }

    /// @notice Manually set price — for any test scenario
    function setPrice(int256 newPrice) external onlyOwner {
        int256 old = _price;
        _price = newPrice;
        _roundId++;
        _updatedAt = block.timestamp;
        emit PriceUpdated(old, newPrice, _roundId);
    }

    /// @notice Simulate a price drop — for the demo's trigger moment
    function dropPrice(int256 newPrice) external onlyOwner {
        if (newPrice >= _price) revert PriceNotLower();
        int256 old = _price;
        _price = newPrice;
        _roundId++;
        _updatedAt = block.timestamp;
        emit PriceUpdated(old, newPrice, _roundId);
    }

    function decimals() external view override returns (uint8) { return _decimals; }
    function description() external view override returns (string memory) { return _description; }
    function version() external pure override returns (uint256) { return 1; }
    function getPrice() external view returns (int256) { return _price; }

    function getRoundData(uint80 roundId_) external view override returns (
        uint80, int256, uint256, uint256, uint80
    ) {
        return (roundId_, _price, _updatedAt, _updatedAt, roundId_);
    }

    function latestRoundData() external view override returns (
        uint80, int256, uint256, uint256, uint80
    ) {
        return (_roundId, _price, _updatedAt, _updatedAt, _roundId);
    }
}
