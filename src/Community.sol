// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title Community Contribution Tracking and Reward Distribution
/// @notice This contract manages contributions and distributes rewards proportionally based on contribution points
/// @dev Implements period-based reward distribution with reentrancy protection
contract Community is ReentrancyGuard {
    /*//////////////////////////////////////////////////////////////
                                 STRUCTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Represents a single contribution in the community
    struct Contribution {
        uint256 id;
        address contributor;
        string title;
        uint256 points;
        uint256 timestamp;
        uint256 periodId;
    }

    /// @notice Represents a reward distribution period
    struct Period {
        uint256 id;
        uint256 startTime;
        uint256 endTime;
        uint256 totalPoints;
        uint256 rewardPool;
        bool isActive;
    }

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice The name of the community
    string public name;

    /// @notice Description of the community's purpose
    string public description;

    /// @notice Address of the community administrator
    address public admin;

    /// @notice Timestamp when the community was created
    uint256 public immutable createdAt;

    /// @notice Array of all contributions ever made
    Contribution[] public contributions;

    /// @notice Total number of contributions
    uint256 public contributionCount;

    /// @notice Array of all reward periods
    Period[] public periods;

    /// @notice ID of the currently active period
    uint256 public currentPeriodId;

    /// @notice Tracks points earned by each user in each period
    /// @dev periodId => user address => points
    mapping(uint256 => mapping(address => uint256)) public userPointsPerPeriod;

    /// @notice Tracks whether a user has claimed rewards for a period
    /// @dev periodId => user address => claimed status
    mapping(uint256 => mapping(address => bool)) public hasClaimed;

    /// @notice Tracks total lifetime points for each user
    /// @dev user address => total points
    mapping(address => uint256) public totalUserPoints;

    /*//////////////////////////////////////////////////////////////
                            CUSTOM ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when caller is not the admin
    error OnlyAdmin();

    /// @notice Thrown when a period ID doesn't exist
    error PeriodNotFound();

    /// @notice Thrown when trying to close or claim from an active period
    error PeriodStillActive();

    /// @notice Thrown when user tries to claim rewards twice
    error AlreadyClaimed();

    /// @notice Thrown when user has no points in a period
    error NoPointsInPeriod();

    /// @notice Thrown when ETH transfer fails
    error TransferFailed();

    /// @notice Thrown when zero address is provided
    error ZeroAddress();

    /// @notice Thrown when invalid points value is provided
    error InvalidPoints();

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a new contribution is added
    event ContributionAdded(
        uint256 indexed id,
        address indexed contributor,
        uint256 points,
        uint256 indexed periodId,
        string title
    );

    /// @notice Emitted when rewards are deposited to a period
    event RewardsDeposited(uint256 amount, uint256 indexed periodId);

    /// @notice Emitted when a period is closed
    event PeriodClosed(
        uint256 indexed periodId,
        uint256 totalPoints,
        uint256 rewardPool
    );

    /// @notice Emitted when a user claims their rewards
    event RewardsClaimed(
        address indexed user,
        uint256 indexed periodId,
        uint256 amount
    );

    /// @notice Emitted when admin address is updated
    event AdminUpdated(address indexed oldAdmin, address indexed newAdmin);

    /*//////////////////////////////////////////////////////////////
                              MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Restricts function access to admin only
    modifier onlyAdmin() {
        if (msg.sender != admin) revert OnlyAdmin();
        _;
    }

    /// @notice Validates that a period exists
    /// @param _periodId The period ID to check
    modifier periodExists(uint256 _periodId) {
        if (_periodId >= periods.length) revert PeriodNotFound();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Initializes the community with basic information
    /// @param _name Name of the community
    /// @param _description Description of the community
    /// @param _admin Address of the community administrator
    constructor(
        string memory _name,
        string memory _description,
        address _admin
    ) {
        if (_admin == address(0)) revert ZeroAddress();

        name = _name;
        description = _description;
        admin = _admin;
        createdAt = block.timestamp;

        // Create the first active period
        periods.push(
            Period({
                id: 0,
                startTime: block.timestamp,
                endTime: 0,
                totalPoints: 0,
                rewardPool: 0,
                isActive: true
            })
        );
        currentPeriodId = 0;
    }

    /*//////////////////////////////////////////////////////////////
                          ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Adds a new contribution to the current period
    /// @param contributor Address of the contributor
    /// @param title Title or description of the contribution
    /// @param points Points awarded for this contribution
    function addContribution(
        address contributor,
        string calldata title,
        uint256 points
    ) external onlyAdmin {
        if (contributor == address(0)) revert ZeroAddress();
        if (points == 0) revert InvalidPoints();

        uint256 contributionId = contributionCount;

        // Create and store the contribution
        contributions.push(
            Contribution({
                id: contributionId,
                contributor: contributor,
                title: title,
                points: points,
                timestamp: block.timestamp,
                periodId: currentPeriodId
            })
        );

        // Update mappings
        userPointsPerPeriod[currentPeriodId][contributor] += points;
        totalUserPoints[contributor] += points;
        periods[currentPeriodId].totalPoints += points;
        contributionCount++;

        emit ContributionAdded(
            contributionId,
            contributor,
            points,
            currentPeriodId,
            title
        );
    }

    /// @notice Deposits ETH rewards to the current period's reward pool
    /// @dev Payable function to accept ETH
    function depositRewards() external payable onlyAdmin {
        periods[currentPeriodId].rewardPool += msg.value;
        emit RewardsDeposited(msg.value, currentPeriodId);
    }

    /// @notice Closes the current period and creates a new one
    /// @dev Can only be called by admin
    function closePeriod() external onlyAdmin {
        Period storage currentPeriod = periods[currentPeriodId];
        currentPeriod.isActive = false;
        currentPeriod.endTime = block.timestamp;

        emit PeriodClosed(
            currentPeriodId,
            currentPeriod.totalPoints,
            currentPeriod.rewardPool
        );

        // Create new period
        uint256 newPeriodId = currentPeriodId + 1;
        periods.push(
            Period({
                id: newPeriodId,
                startTime: block.timestamp,
                endTime: 0,
                totalPoints: 0,
                rewardPool: 0,
                isActive: true
            })
        );
        currentPeriodId = newPeriodId;
    }

    /// @notice Updates the admin address
    /// @param newAdmin Address of the new administrator
    function updateAdmin(address newAdmin) external onlyAdmin {
        if (newAdmin == address(0)) revert ZeroAddress();
        
        address oldAdmin = admin;
        admin = newAdmin;
        
        emit AdminUpdated(oldAdmin, newAdmin);
    }

    /*//////////////////////////////////////////////////////////////
                          USER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Claims proportional rewards for a specific period
    /// @param periodId The period ID to claim rewards from
    /// @dev Uses nonReentrant modifier to prevent reentrancy attacks
    function claimRewards(uint256 periodId)
        external
        nonReentrant
        periodExists(periodId)
    {
        Period storage period = periods[periodId];

        // Validate claim conditions
        if (period.isActive) revert PeriodStillActive();
        if (hasClaimed[periodId][msg.sender]) revert AlreadyClaimed();

        uint256 userPoints = userPointsPerPeriod[periodId][msg.sender];
        if (userPoints == 0) revert NoPointsInPeriod();

        // Calculate proportional reward
        uint256 claimableAmount = (userPoints * period.rewardPool) /
            period.totalPoints;

        // Mark as claimed before transfer
        hasClaimed[periodId][msg.sender] = true;

        // Transfer rewards
        (bool success, ) = msg.sender.call{value: claimableAmount}("");
        if (!success) revert TransferFailed();

        emit RewardsClaimed(msg.sender, periodId, claimableAmount);
    }

    /*//////////////////////////////////////////////////////////////
                          VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Calculates the claimable amount for a user in a specific period
    /// @param user Address of the user
    /// @param periodId The period ID to check
    /// @return The amount of ETH the user can claim
    function getClaimableAmount(address user, uint256 periodId)
        external
        view
        periodExists(periodId)
        returns (uint256)
    {
        if (hasClaimed[periodId][user]) return 0;

        uint256 userPoints = userPointsPerPeriod[periodId][user];
        if (userPoints == 0) return 0;

        Period storage period = periods[periodId];
        if (period.totalPoints == 0) return 0;

        return (userPoints * period.rewardPool) / period.totalPoints;
    }

    /// @notice Gets the points a user earned in a specific period
    /// @param user Address of the user
    /// @param periodId The period ID to check
    /// @return The number of points
    function getUserPoints(address user, uint256 periodId)
        external
        view
        periodExists(periodId)
        returns (uint256)
    {
        return userPointsPerPeriod[periodId][user];
    }

    /// @notice Gets information about a specific period
    /// @param periodId The period ID to query
    /// @return The Period struct
    function getPeriodInfo(uint256 periodId)
        external
        view
        periodExists(periodId)
        returns (Period memory)
    {
        return periods[periodId];
    }

    /// @notice Gets all contributions
    /// @return Array of all Contribution structs
    function getContributions() external view returns (Contribution[] memory) {
        return contributions;
    }

    /// @notice Gets the total number of contributions
    /// @return The total count
    function getTotalContributions() external view returns (uint256) {
        return contributionCount;
    }

    /// @notice Gets comprehensive community statistics
    /// @return communityName The name of the community
    /// @return communityDescription The description of the community
    /// @return communityAdmin The admin address
    /// @return totalContributions Total number of contributions
    /// @return activePeriodId Current period ID
    /// @return communityCreatedAt Timestamp when community was created
    function getCommunityStats()
        external
        view
        returns (
            string memory communityName,
            string memory communityDescription,
            address communityAdmin,
            uint256 totalContributions,
            uint256 activePeriodId,
            uint256 communityCreatedAt
        )
    {
        return (
            name,
            description,
            admin,
            contributionCount,
            currentPeriodId,
            createdAt
        );
    }
}
