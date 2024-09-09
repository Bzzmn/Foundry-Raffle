// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// internal & private view & pure functions
// external & public view & pure functions

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title Raffle contract
 * @author Bzzmn
 * @notice This contract is a raffle contract.
 * @dev Implements Chainlink VRFv2.5
 */

// Imports
import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

contract Raffle is VRFConsumerBaseV2Plus {
    /** Errors */
    error Raffle_NotEnoughEthSent();
    error Raffle_TransferFailed();
    error Raffle_NotEnoughTimePassed();
    error Raffle_NotOpen();
    error Raffle_UpkeepNotNeeded(
        uint256 balance,
        uint256 participants,
        uint256 state
    );

    /** Type Declarations */
    enum RaffleState {
        OPEN,
        CALCULATING
    }

    /** State Variables */
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;
    uint256 private immutable i_entranceFee;
    uint256 private immutable i_interval; // @dev The interval in which the raffle will be held in seconds
    bytes32 private immutable i_keyHash;
    uint256 private immutable i_subscriptionId;
    uint32 private immutable i_callbackGasLimit;
    address payable[] private s_participants;
    uint256 private s_lastTimeStamp;
    address private s_recentWinner;
    RaffleState private s_raffleState;

    /** Events */
    event RaffleEntered(address indexed participant);
    event WinnerPicked(address indexed winner);

    constructor(
        uint256 entranceFee,
        uint256 interval,
        address vrfCoordinator,
        bytes32 gasLane,
        uint256 subscriptionId,
        uint32 callbackGasLimit
    ) VRFConsumerBaseV2Plus(vrfCoordinator) {
        i_entranceFee = entranceFee;
        i_interval = interval;
        i_keyHash = gasLane;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;

        s_lastTimeStamp = block.timestamp;
        s_raffleState = RaffleState.OPEN;
    }

    function enterRaffle() external payable {
        // Enter the raffle
        // require(msg.value >= i_entranceFee, "Not enough ETH sent to enter the raffle");
        if (s_raffleState == RaffleState.CALCULATING) {
            revert Raffle_NotOpen();
        }

        if (msg.value < i_entranceFee) {
            revert Raffle_NotEnoughEthSent();
        }

        s_participants.push(payable(msg.sender));
        // Emit event
        //1. Makes migration easier
        //2. Makes it easier to track the transaction
        //3, Makes frontend indexing easier
        emit RaffleEntered(msg.sender);
    }

    /**
     * @dev - This is the function that the Chainlink nodes will call to check
     * if the contract is ready to have a winner picked.
     * The following should be true in order for upkeepNeeded to be true:
     * 1. The time interval has passed
     * 2. The raffle is in the OPEN state
     * 3. There are participants in the raffle so the contract has ETH to give away
     * 4. Implicitly, the contract has enough LINK to pay for the VRF request.
     * @param - ignored
     * @return upkeepNeeded - A boolean that is true if the contract needs to call the fulfillRandomWords function
     */

    function checkUpkeep(
        bytes memory /* checkData */
    ) public view returns (bool upkeepNeeded, bytes memory /* performData */) {
        bool intervalPassed = (block.timestamp - s_lastTimeStamp >= i_interval);
        bool isOpen = s_raffleState == RaffleState.OPEN;
        bool hasParticipants = s_participants.length > 0;
        bool hasBalance = address(this).balance > 0;
        upkeepNeeded =
            intervalPassed &&
            isOpen &&
            hasParticipants &&
            hasBalance;
        return (upkeepNeeded, "");
    }

    // We need to:
    // 1. Get a random number
    // 2. Use the random number to pick the winner
    function performUpkeep(bytes calldata /* performData */) external {
        // check if enough time has passed
        (bool upkeepNeeded, ) = checkUpkeep("");
        if (!upkeepNeeded) {
            revert Raffle_UpkeepNotNeeded(
                address(this).balance,
                s_participants.length,
                uint256(s_raffleState)
            );
        }
        // change the state
        s_raffleState = RaffleState.CALCULATING;

        VRFV2PlusClient.RandomWordsRequest memory request = VRFV2PlusClient
            .RandomWordsRequest({
                keyHash: i_keyHash,
                subId: i_subscriptionId,
                requestConfirmations: REQUEST_CONFIRMATIONS,
                callbackGasLimit: i_callbackGasLimit,
                numWords: NUM_WORDS,
                extraArgs: VRFV2PlusClient._argsToBytes(
                    VRFV2PlusClient.ExtraArgsV1({nativePayment: false})
                )
            });

        uint256 requestId = s_vrfCoordinator.requestRandomWords(request);

        // get a random number to chainlink vrf
        // 1. request a rng
        // 2. get the rng
    }

    // CEI: Checks, Effects, Interactions Pattern
    function fulfillRandomWords(
        uint256 requestId,
        uint256[] calldata randomWords
    ) internal override {
        // Checks

        // Effects (internal contract state)
        uint256 winnerIndex = randomWords[0] % s_participants.length;
        address payable winner = s_participants[winnerIndex];
        s_recentWinner = winner;
        s_participants = new address payable[](0);
        s_lastTimeStamp = block.timestamp;
        s_raffleState = RaffleState.OPEN;
        emit WinnerPicked(winner);

        // Interactions (external contract calls)
        (bool success, ) = winner.call{value: address(this).balance}("");
        if (!success) {
            revert Raffle_TransferFailed();
        }
    }

    /** Getter Functions */

    function getEntranceFee() external view returns (uint256) {
        return i_entranceFee;
    }
}
