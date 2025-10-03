// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./Context.sol";

/**
 * @title Pausable
 * @notice Contract module which allows children to implement an emergency stop
 * mechanism that can be triggered by an authorized account with governance oversight.
 * @dev This module is used through inheritance. It will make available the
 * modifiers `whenNotPaused` and `whenPaused`, which can be applied to
 * the functions of your contract.
 */
abstract contract Pausable is Context {
    
    // Pause states
    bool private _paused;
    bool private _emergencyPaused;
    
    // Governance contract that can pause/unpause
    address public governance;
    
    // Emergency pause settings
    uint256 public emergencyPauseInitiated;
    uint256 public constant EMERGENCY_PAUSE_DURATION = 24 hours;
    
    // Circuit breaker settings
    uint256 public dailyTransactionLimit = 1000; // Max transactions per day
    uint256 public dailyVolumeLimit = 10000 ether; // Max CRO volume per day
    uint256 public currentDayStart;
    uint256 public dailyTransactionCount;
    uint256 public dailyVolumeCount;
    
    // Unusual activity detection
    mapping(address => uint256) public userDailyTransactions;
    mapping(address => uint256) public userDailyVolume;
    uint256 public constant MAX_USER_DAILY_TRANSACTIONS = 50;
    uint256 public constant MAX_USER_DAILY_VOLUME = 1000 ether;
    
    // Events
    event Paused(address account);
    event Unpaused(address account);
    event EmergencyPaused(address account, string reason);
    event EmergencyUnpaused(address account);
    event GovernanceChanged(address indexed previousGovernance, address indexed newGovernance);
    event CircuitBreakerTriggered(string reason, uint256 value);
    event UnusualActivityDetected(address indexed user, string reason, uint256 value);
    event LimitsUpdated(uint256 dailyTxLimit, uint256 dailyVolumeLimit);
    
    // Modifiers
    modifier whenNotPaused() {
        _requireNotPaused();
        _;
    }
    
    modifier whenPaused() {
        _requirePaused();
        _;
    }
    
    modifier onlyGovernance() {
        require(_msgSender() == governance, "Pausable: caller is not governance");
        _;
    }
    
    modifier circuitBreaker(uint256 value) {
        _checkCircuitBreaker(value);
        _;
    }
    
    constructor(address _governance) {
        require(_governance != address(0), "Pausable: governance cannot be zero address");
        governance = _governance;
        _paused = false;
        _emergencyPaused = false;
        currentDayStart = block.timestamp;
    }
    
    /**
     * @notice Returns true if the contract is paused, and false otherwise.
     */
    function paused() public view virtual returns (bool) {
        return _paused || _emergencyPaused;
    }
    
    /**
     * @notice Returns true if emergency pause is active
     */
    function emergencyPaused() public view virtual returns (bool) {
        return _emergencyPaused;
    }
    
    /**
     * @notice Throws if the contract is paused.
     */
    function _requireNotPaused() internal view virtual {
        require(!paused(), "Pausable: paused");
    }
    
    /**
     * @notice Throws if the contract is not paused.
     */
    function _requirePaused() internal view virtual {
        require(paused(), "Pausable: not paused");
    }
    
    /**
     * @notice Triggers stopped state (governance only)
     */
    function pause() public virtual onlyGovernance {
        _paused = true;
        emit Paused(_msgSender());
    }
    
    /**
     * @notice Returns to normal state (governance only)
     */
    function unpause() public virtual onlyGovernance {
        _paused = false;
        emit Unpaused(_msgSender());
    }
    
    /**
     * @notice Emergency pause with automatic unpause after 24 hours
     * @dev Can be called by governance or triggered automatically by circuit breakers
     */
    function emergencyPause(string memory reason) public virtual onlyGovernance {
        require(!_emergencyPaused, "Pausable: already emergency paused");
        
        _emergencyPaused = true;
        emergencyPauseInitiated = block.timestamp;
        
        emit EmergencyPaused(_msgSender(), reason);
    }
    
    /**
     * @notice Remove emergency pause (governance only)
     */
    function emergencyUnpause() public virtual onlyGovernance {
        require(_emergencyPaused, "Pausable: not emergency paused");
        
        _emergencyPaused = false;
        emergencyPauseInitiated = 0;
        
        emit EmergencyUnpaused(_msgSender());
    }
    
    /**
     * @notice Auto-unpause after emergency pause duration
     */
    function autoEmergencyUnpause() public virtual {
        require(_emergencyPaused, "Pausable: not emergency paused");
        require(
            block.timestamp >= emergencyPauseInitiated + EMERGENCY_PAUSE_DURATION,
            "Pausable: emergency pause duration not met"
        );
        
        _emergencyPaused = false;
        emergencyPauseInitiated = 0;
        
        emit EmergencyUnpaused(address(0)); // address(0) indicates auto-unpause
    }
    
    /**
     * @notice Circuit breaker to detect unusual activity
     */
    function _checkCircuitBreaker(uint256 value) internal {
        // Reset daily counters if new day
        if (block.timestamp >= currentDayStart + 1 days) {
            currentDayStart = block.timestamp;
            dailyTransactionCount = 0;
            dailyVolumeCount = 0;
        }
        
        // Check global daily limits
        dailyTransactionCount++;
        dailyVolumeCount += value;
        
        if (dailyTransactionCount > dailyTransactionLimit) {
            _triggerCircuitBreaker("Daily transaction limit exceeded", dailyTransactionCount);
        }
        
        if (dailyVolumeCount > dailyVolumeLimit) {
            _triggerCircuitBreaker("Daily volume limit exceeded", dailyVolumeCount);
        }
        
        // Check user-specific limits
        address user = _msgSender();
        userDailyTransactions[user]++;
        userDailyVolume[user] += value;
        
        if (userDailyTransactions[user] > MAX_USER_DAILY_TRANSACTIONS) {
            emit UnusualActivityDetected(
                user, 
                "User daily transaction limit exceeded", 
                userDailyTransactions[user]
            );
            // Could trigger emergency pause for this user or globally
        }
        
        if (userDailyVolume[user] > MAX_USER_DAILY_VOLUME) {
            emit UnusualActivityDetected(
                user, 
                "User daily volume limit exceeded", 
                userDailyVolume[user]
            );
            // Could trigger emergency pause for this user or globally
        }
        
        // Check for suspicious patterns (large single transaction)
        if (value > 1000 ether) {
            emit UnusualActivityDetected(
                user, 
                "Large single transaction detected", 
                value
            );
        }
    }
    
    /**
     * @notice Trigger circuit breaker and emergency pause
     */
    function _triggerCircuitBreaker(string memory reason, uint256 value) internal {
        emit CircuitBreakerTriggered(reason, value);
        
        // Auto-trigger emergency pause
        if (!_emergencyPaused) {
            _emergencyPaused = true;
            emergencyPauseInitiated = block.timestamp;
            emit EmergencyPaused(address(this), reason);
        }
    }
    
    /**
     * @notice Update circuit breaker limits (governance only)
     */
    function updateLimits(
        uint256 _dailyTransactionLimit,
        uint256 _dailyVolumeLimit
    ) external onlyGovernance {
        require(_dailyTransactionLimit > 0, "Pausable: invalid transaction limit");
        require(_dailyVolumeLimit > 0, "Pausable: invalid volume limit");
        
        dailyTransactionLimit = _dailyTransactionLimit;
        dailyVolumeLimit = _dailyVolumeLimit;
        
        emit LimitsUpdated(_dailyTransactionLimit, _dailyVolumeLimit);
    }
    
    /**
     * @notice Change governance address (current governance only)
     */
    function changeGovernance(address newGovernance) external onlyGovernance {
        require(newGovernance != address(0), "Pausable: new governance cannot be zero address");
        
        address oldGovernance = governance;
        governance = newGovernance;
        
        emit GovernanceChanged(oldGovernance, newGovernance);
    }
    
    /**
     * @notice Get current circuit breaker status
     */
    function getCircuitBreakerStatus() 
        external 
        view 
        returns (
            uint256 currentDayTransactions,
            uint256 currentDayVolume,
            uint256 txLimit,
            uint256 volumeLimit,
            uint256 dayStartTime,
            bool isPaused,
            bool isEmergencyPaused
        ) 
    {
        return (
            dailyTransactionCount,
            dailyVolumeCount,
            dailyTransactionLimit,
            dailyVolumeLimit,
            currentDayStart,
            _paused,
            _emergencyPaused
        );
    }
    
    /**
     * @notice Get user activity for current day
     */
    function getUserActivity(address user) 
        external 
        view 
        returns (
            uint256 transactions,
            uint256 volume,
            bool nearTxLimit,
            bool nearVolumeLimit
        ) 
    {
        uint256 userTx = userDailyTransactions[user];
        uint256 userVol = userDailyVolume[user];
        
        return (
            userTx,
            userVol,
            userTx > (MAX_USER_DAILY_TRANSACTIONS * 80 / 100), // 80% of limit
            userVol > (MAX_USER_DAILY_VOLUME * 80 / 100)       // 80% of limit
        );
    }
    
    /**
     * @notice Reset user daily counters (governance only, for emergency situations)
     */
    function resetUserCounters(address user) external onlyGovernance {
        userDailyTransactions[user] = 0;
        userDailyVolume[user] = 0;
    }
    
    /**
     * @notice Reset global daily counters (governance only, for emergency situations)
     */
    function resetGlobalCounters() external onlyGovernance {
        dailyTransactionCount = 0;
        dailyVolumeCount = 0;
        currentDayStart = block.timestamp;
    }
    
    /**
     * @notice Check if emergency pause is about to expire
     */
    function emergencyPauseTimeRemaining() external view returns (uint256) {
        if (!_emergencyPaused) return 0;
        
        uint256 elapsed = block.timestamp - emergencyPauseInitiated;
        if (elapsed >= EMERGENCY_PAUSE_DURATION) return 0;
        
        return EMERGENCY_PAUSE_DURATION - elapsed;
    }
}
