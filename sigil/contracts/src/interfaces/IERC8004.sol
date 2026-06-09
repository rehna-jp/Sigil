// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IERC8004Registry
 * @notice Interface for ERC-8004: AI Agent Identity and Reputation Standard
 * @dev Minimal implementation for Sigil's AI agent authorization
 */
interface IERC8004Registry {
    // ============ Events ============

    /// @notice Emitted when an agent is registered
    event AgentRegistered(
        address indexed agent,
        bytes32 capabilities,
        string metadataURI,
        uint256 timestamp
    );

    /// @notice Emitted when agent reputation is updated
    event ReputationUpdated(
        address indexed agent,
        int256 delta,
        uint256 newReputation
    );

    /// @notice Emitted when agent is deactivated
    event AgentDeactivated(address indexed agent, uint256 timestamp);

    // ============ Structs ============

    /// @notice Agent information
    struct AgentInfo {
        bool registered;
        bool active;
        bytes32 capabilities;    // Bitfield of agent capabilities
        uint256 reputation;      // Agent reputation score
        string metadataURI;      // IPFS or HTTP URI to agent metadata
        uint256 registeredAt;    // Registration timestamp
    }

    // ============ Functions ============

    /**
     * @notice Register a new AI agent
     * @param agent Address of the agent
     * @param capabilities Bitfield representing agent capabilities
     * @param metadataURI URI to agent metadata (IPFS/HTTP)
     */
    function registerAgent(
        address agent,
        bytes32 capabilities,
        string calldata metadataURI
    ) external;

    /**
     * @notice Get agent information
     * @param agent Address of the agent
     * @return info Agent information struct
     */
    function getAgentInfo(address agent)
        external
        view
        returns (AgentInfo memory info);

    /**
     * @notice Update agent reputation
     * @param agent Address of the agent
     * @param delta Change in reputation (positive or negative)
     */
    function updateReputation(address agent, int256 delta) external;

    /**
     * @notice Check if agent is authorized for a specific capability
     * @param agent Address of the agent
     * @param capability Capability to check
     * @return bool True if agent has the capability
     */
    function isAuthorized(address agent, bytes32 capability)
        external
        view
        returns (bool);

    /**
     * @notice Deactivate an agent
     * @param agent Address of the agent to deactivate
     */
    function deactivateAgent(address agent) external;

    /**
     * @notice Check if agent is registered and active
     * @param agent Address of the agent
     * @return bool True if agent is registered and active
     */
    function isActiveAgent(address agent) external view returns (bool);
}

/**
 * @title ERC8004Registry
 * @notice Minimal implementation of ERC-8004 for Sigil hackathon
 * @dev Production version should use standardized implementation
 */
contract ERC8004Registry is IERC8004Registry {
    // ============ State Variables ============

    /// @notice Mapping of agent addresses to their information
    mapping(address => AgentInfo) public agents;

    /// @notice Owner of the registry (can register agents)
    address public owner;

    /// @notice Capability constants
    bytes32 public constant INTENT_DECOMPOSER = keccak256("INTENT_DECOMPOSER");
    bytes32 public constant WATCHER_CREATOR = keccak256("WATCHER_CREATOR");
    bytes32 public constant TRIGGER_EXECUTOR = keccak256("TRIGGER_EXECUTOR");

    // ============ Modifiers ============

    modifier onlyOwner() {
        require(msg.sender == owner, "ERC8004: not owner");
        _;
    }

    // ============ Constructor ============

    constructor() {
        owner = msg.sender;
    }

    // ============ External Functions ============

    /**
     * @inheritdoc IERC8004Registry
     */
    function registerAgent(
        address agent,
        bytes32 capabilities,
        string calldata metadataURI
    ) external override onlyOwner {
        require(agent != address(0), "ERC8004: zero address");
        require(!agents[agent].registered, "ERC8004: already registered");

        agents[agent] = AgentInfo({
            registered: true,
            active: true,
            capabilities: capabilities,
            reputation: 100, // Start with base reputation
            metadataURI: metadataURI,
            registeredAt: block.timestamp
        });

        emit AgentRegistered(agent, capabilities, metadataURI, block.timestamp);
    }

    /**
     * @inheritdoc IERC8004Registry
     */
    function getAgentInfo(address agent)
        external
        view
        override
        returns (AgentInfo memory info)
    {
        return agents[agent];
    }

    /**
     * @inheritdoc IERC8004Registry
     */
    function updateReputation(address agent, int256 delta) external override {
        require(agents[agent].registered, "ERC8004: not registered");

        // Only owner or the agent's associated contracts can update reputation
        require(
            msg.sender == owner || msg.sender == agent,
            "ERC8004: not authorized"
        );

        uint256 currentReputation = agents[agent].reputation;
        uint256 newReputation;

        if (delta >= 0) {
            newReputation = currentReputation + uint256(delta);
        } else {
            uint256 decrease = uint256(-delta);
            newReputation = currentReputation > decrease
                ? currentReputation - decrease
                : 0;
        }

        agents[agent].reputation = newReputation;

        emit ReputationUpdated(agent, delta, newReputation);
    }

    /**
     * @inheritdoc IERC8004Registry
     */
    function isAuthorized(address agent, bytes32 capability)
        external
        view
        override
        returns (bool)
    {
        if (!agents[agent].active || !agents[agent].registered) {
            return false;
        }

        // Check if agent has the specific capability
        return (agents[agent].capabilities & capability) == capability;
    }

    /**
     * @inheritdoc IERC8004Registry
     */
    function deactivateAgent(address agent) external override onlyOwner {
        require(agents[agent].registered, "ERC8004: not registered");
        agents[agent].active = false;

        emit AgentDeactivated(agent, block.timestamp);
    }

    /**
     * @inheritdoc IERC8004Registry
     */
    function isActiveAgent(address agent) external view override returns (bool) {
        return agents[agent].registered && agents[agent].active;
    }

    /**
     * @notice Transfer ownership of the registry
     * @param newOwner Address of new owner
     */
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "ERC8004: zero address");
        owner = newOwner;
    }
}
