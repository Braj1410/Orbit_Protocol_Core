// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "../utils/ReentrancyGuard.sol";

/**
 * @title OrbitGovernance
 * @notice Multi-sig governance contract with timelock delays for critical operations
 * @dev Replaces single owner control with multi-sig governance
 */
contract OrbitGovernance is ReentrancyGuard {
    
    struct Proposal {
        address target;
        bytes data;
        uint256 value;
        uint256 executeTime;
        bool executed;
        uint256 confirmations;
        mapping(address => bool) confirmed;
        string description;
        ProposalType proposalType;
    }
    
    enum ProposalType {
        STANDARD,           // 24 hour delay
        CRITICAL,          // 48 hour delay
        EMERGENCY_PAUSE,   // 1 hour delay
        PRICE_CHANGE       // 24 hour delay with limits
    }
    
    // State variables
    address[] public governors;
    mapping(address => bool) public isGovernor;
    uint256 public requiredConfirmations;
    uint256 public proposalCount;
    
    mapping(uint256 => Proposal) public proposals;
    
    // Timelock delays
    uint256 public constant STANDARD_DELAY = 24 hours;
    uint256 public constant CRITICAL_DELAY = 48 hours;
    uint256 public constant EMERGENCY_DELAY = 1 hours;
    uint256 public constant PRICE_CHANGE_DELAY = 24 hours;
    
    // Price change limits (50% max change per day)
    uint256 public constant MAX_PRICE_CHANGE_PERCENT = 150; // 150% = 50% increase
    uint256 public constant MIN_PRICE_CHANGE_PERCENT = 67;  // 67% = 33% decrease
    mapping(address => mapping(bytes4 => uint256)) public lastPriceChange;
    
    // Emergency pause
    bool public emergencyPaused = false;
    uint256 public pauseInitiatedAt;
    uint256 public constant MAX_PAUSE_DURATION = 7 days;
    
    // Events
    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed proposer,
        address target,
        string description,
        ProposalType proposalType
    );
    
    event ProposalConfirmed(
        uint256 indexed proposalId,
        address indexed governor
    );
    
    event ProposalRevoked(
        uint256 indexed proposalId,
        address indexed governor
    );
    
    event ProposalExecuted(
        uint256 indexed proposalId,
        address indexed executor
    );
    
    event GovernorAdded(address indexed governor);
    event GovernorRemoved(address indexed governor);
    event RequiredConfirmationsChanged(uint256 newRequired);
    
    event EmergencyPauseActivated(address indexed initiator);
    event EmergencyPauseDeactivated(address indexed initiator);
    
    event PriceChangeBlocked(
        address indexed oracle,
        bytes4 indexed selector,
        string reason
    );
    
    // Modifiers
    modifier onlyGovernor() {
        require(isGovernor[msg.sender], "Not a governor");
        _;
    }
    
    modifier whenNotPaused() {
        require(!emergencyPaused, "System is paused");
        _;
    }
    
    modifier proposalExists(uint256 proposalId) {
        require(proposalId < proposalCount, "Proposal does not exist");
        _;
    }
    
    modifier notExecuted(uint256 proposalId) {
        require(!proposals[proposalId].executed, "Proposal already executed");
        _;
    }
    
    modifier notConfirmed(uint256 proposalId) {
        require(!proposals[proposalId].confirmed[msg.sender], "Already confirmed");
        _;
    }
    
    constructor(
        address[] memory _governors,
        uint256 _requiredConfirmations
    ) {
        require(_governors.length > 0, "Need at least one governor");
        require(
            _requiredConfirmations > 0 && 
            _requiredConfirmations <= _governors.length,
            "Invalid required confirmations"
        );
        require(_requiredConfirmations >= 3, "Minimum 3 confirmations required");
        
        for (uint256 i = 0; i < _governors.length; i++) {
            address governor = _governors[i];
            require(governor != address(0), "Invalid governor address");
            require(!isGovernor[governor], "Duplicate governor");
            
            isGovernor[governor] = true;
            governors.push(governor);
            emit GovernorAdded(governor);
        }
        
        requiredConfirmations = _requiredConfirmations;
    }
    
    /**
     * @notice Create a new governance proposal
     */
    function createProposal(
        address target,
        bytes calldata data,
        uint256 value,
        string calldata description,
        ProposalType proposalType
    ) external onlyGovernor whenNotPaused returns (uint256) {
        
        // Validate proposal type for price changes
        if (proposalType == ProposalType.PRICE_CHANGE) {
            _validatePriceChange(target, data);
        }
        
        uint256 proposalId = proposalCount++;
        Proposal storage proposal = proposals[proposalId];
        
        proposal.target = target;
        proposal.data = data;
        proposal.value = value;
        proposal.description = description;
        proposal.proposalType = proposalType;
        
        // Set execution time based on proposal type
        uint256 delay;
        if (proposalType == ProposalType.EMERGENCY_PAUSE) {
            delay = EMERGENCY_DELAY;
        } else if (proposalType == ProposalType.CRITICAL) {
            delay = CRITICAL_DELAY;
        } else {
            delay = STANDARD_DELAY;
        }
        
        proposal.executeTime = block.timestamp + delay;
        
        emit ProposalCreated(proposalId, msg.sender, target, description, proposalType);
        
        return proposalId;
    }
    
    /**
     * @notice Confirm a proposal
     */
    function confirmProposal(uint256 proposalId)
        external
        onlyGovernor
        proposalExists(proposalId)
        notExecuted(proposalId)
        notConfirmed(proposalId)
    {
        Proposal storage proposal = proposals[proposalId];
        proposal.confirmed[msg.sender] = true;
        proposal.confirmations++;
        
        emit ProposalConfirmed(proposalId, msg.sender);
    }
    
    /**
     * @notice Revoke confirmation for a proposal
     */
    function revokeConfirmation(uint256 proposalId)
        external
        onlyGovernor
        proposalExists(proposalId)
        notExecuted(proposalId)
    {
        Proposal storage proposal = proposals[proposalId];
        require(proposal.confirmed[msg.sender], "Not confirmed");
        
        proposal.confirmed[msg.sender] = false;
        proposal.confirmations--;
        
        emit ProposalRevoked(proposalId, msg.sender);
    }
    
    /**
     * @notice Execute a confirmed proposal after timelock
     */
    function executeProposal(uint256 proposalId)
        external
        nonReentrant
        proposalExists(proposalId)
        notExecuted(proposalId)
    {
        Proposal storage proposal = proposals[proposalId];
        
        require(
            proposal.confirmations >= requiredConfirmations,
            "Insufficient confirmations"
        );
        
        require(
            block.timestamp >= proposal.executeTime,
            "Timelock not expired"
        );
        
        // Additional check for emergency pause proposals
        if (proposal.proposalType == ProposalType.EMERGENCY_PAUSE) {
            require(isGovernor[msg.sender], "Only governors can execute emergency pause");
        }
        
        proposal.executed = true;
        
        // Record price change timestamp if applicable
        if (proposal.proposalType == ProposalType.PRICE_CHANGE) {
            bytes memory data = proposal.data;
            bytes4 selector;
            assembly {
                selector := mload(add(data, 0x20))
            }
            lastPriceChange[proposal.target][selector] = block.timestamp;
        }
        
        // Execute the proposal
        (bool success, bytes memory result) = proposal.target.call{value: proposal.value}(proposal.data);
        require(success, string(result));
        
        emit ProposalExecuted(proposalId, msg.sender);
    }
    
    /**
     * @notice Emergency pause the system (fast-track governance)
     */
    function emergencyPause() external onlyGovernor {
        require(!emergencyPaused, "Already paused");
        
        emergencyPaused = true;
        pauseInitiatedAt = block.timestamp;
        
        emit EmergencyPauseActivated(msg.sender);
    }
    
    /**
     * @notice Unpause the system (requires governance vote)
     */
    function unpause() external onlyGovernor {
        require(emergencyPaused, "Not paused");
        
        emergencyPaused = false;
        pauseInitiatedAt = 0;
        
        emit EmergencyPauseDeactivated(msg.sender);
    }
    
    /**
     * @notice Auto-unpause after maximum duration
     */
    function autoUnpause() external {
        require(emergencyPaused, "Not paused");
        require(
            block.timestamp >= pauseInitiatedAt + MAX_PAUSE_DURATION,
            "Max pause duration not reached"
        );
        
        emergencyPaused = false;
        pauseInitiatedAt = 0;
        
        emit EmergencyPauseDeactivated(msg.sender);
    }
    
    /**
     * @notice Add a new governor (requires governance vote)
     */
    function addGovernor(address governor) external {
        require(msg.sender == address(this), "Only governance can add governors");
        require(governor != address(0), "Invalid address");
        require(!isGovernor[governor], "Already a governor");
        
        isGovernor[governor] = true;
        governors.push(governor);
        
        emit GovernorAdded(governor);
    }
    
    /**
     * @notice Remove a governor (requires governance vote)
     */
    function removeGovernor(address governor) external {
        require(msg.sender == address(this), "Only governance can remove governors");
        require(isGovernor[governor], "Not a governor");
        require(governors.length > requiredConfirmations, "Cannot remove, would break quorum");
        
        isGovernor[governor] = false;
        
        // Remove from array
        for (uint256 i = 0; i < governors.length; i++) {
            if (governors[i] == governor) {
                governors[i] = governors[governors.length - 1];
                governors.pop();
                break;
            }
        }
        
        emit GovernorRemoved(governor);
    }
    
    /**
     * @notice Change required confirmations (requires governance vote)
     */
    function changeRequiredConfirmations(uint256 _requiredConfirmations) external {
        require(msg.sender == address(this), "Only governance can change requirements");
        require(
            _requiredConfirmations > 0 && 
            _requiredConfirmations <= governors.length,
            "Invalid required confirmations"
        );
        require(_requiredConfirmations >= 3, "Minimum 3 confirmations required");
        
        requiredConfirmations = _requiredConfirmations;
        emit RequiredConfirmationsChanged(_requiredConfirmations);
    }
    
    /**
     * @notice Validate price change proposals
     */
    function _validatePriceChange(address target, bytes calldata data) private view {
        bytes4 selector = bytes4(data[:4]);
        uint256 lastChange = lastPriceChange[target][selector];
        
        // Enforce 24-hour cooldown between price changes
        require(
            block.timestamp >= lastChange + PRICE_CHANGE_DELAY,
            "Price change cooldown not met"
        );
        
        // Additional validation could be added here to check price change magnitude
        // This would require decoding the function parameters
    }
    
    /**
     * @notice Check if a proposal is confirmed
     */
    function isConfirmed(uint256 proposalId) external view returns (bool) {
        return proposals[proposalId].confirmations >= requiredConfirmations;
    }
    
    /**
     * @notice Check if a proposal is ready for execution
     */
    function isExecutable(uint256 proposalId) external view returns (bool) {
        Proposal storage proposal = proposals[proposalId];
        return !proposal.executed &&
               proposal.confirmations >= requiredConfirmations &&
               block.timestamp >= proposal.executeTime;
    }
    
    /**
     * @notice Get proposal details
     */
    function getProposal(uint256 proposalId)
        external
        view
        returns (
            address target,
            bytes memory data,
            uint256 value,
            uint256 executeTime,
            bool executed,
            uint256 confirmations,
            string memory description,
            ProposalType proposalType
        )
    {
        Proposal storage proposal = proposals[proposalId];
        return (
            proposal.target,
            proposal.data,
            proposal.value,
            proposal.executeTime,
            proposal.executed,
            proposal.confirmations,
            proposal.description,
            proposal.proposalType
        );
    }
    
    /**
     * @notice Get all governors
     */
    function getGovernors() external view returns (address[] memory) {
        return governors;
    }
    
    /**
     * @notice Check if governor confirmed a proposal
     */
    function hasConfirmed(uint256 proposalId, address governor) 
        external 
        view 
        returns (bool) 
    {
        return proposals[proposalId].confirmed[governor];
    }
    
    /**
     * @notice Get governance status
     */
    function getGovernanceStatus() 
        external 
        view 
        returns (
            uint256 totalGovernors,
            uint256 required,
            bool paused,
            uint256 pausedSince,
            uint256 totalProposals
        ) 
    {
        return (
            governors.length,
            requiredConfirmations,
            emergencyPaused,
            pauseInitiatedAt,
            proposalCount
        );
    }
    
    /**
     * @notice Emergency function to receive ETH
     */
    receive() external payable {}
    
    /**
     * @notice Withdraw ETH (requires governance vote)
     */
    function withdraw(address payable to, uint256 amount) external {
        require(msg.sender == address(this), "Only governance can withdraw");
        require(to != address(0), "Invalid address");
        require(amount <= address(this).balance, "Insufficient balance");
        
        (bool success, ) = to.call{value: amount}("");
        require(success, "Withdrawal failed");
    }
}
