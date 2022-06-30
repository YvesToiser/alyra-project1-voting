// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import "@openzeppelin/contracts/access/Ownable.sol";

contract Voting is Ownable{

    // These variable are specified in the specs.
    struct Voter {
        bool isRegistered;
        bool hasVoted;
        uint votedProposalId;
    }

    struct Proposal {
        string description;
        uint voteCount;
    }

    enum WorkflowStatus {
        RegisteringVoters,
        ProposalsRegistrationStarted,
        ProposalsRegistrationEnded,
        VotingSessionStarted,
        VotingSessionEnded,
        VotesTallied
    }

    // End of mandatory variables

    /**
        Handle the workflow status
        Automatically initialized as -> WorkflowStatus.RegisteringVoters
    */
    WorkflowStatus currentStatus;

    // Whitelist of registered voters and array of proposals.
    // Whitelist is Public so that everybody can see the votes as per the specs.
    mapping(address => Voter) public whitelist;
    Proposal[] proposals;
    // We do arrays of winning proposals to handle case of ex-aequo.
    uint[] winningProposalIds;
    string[] winningProposalsDescriptions;

    /**
        These variables are added for quorum settlement
        uint8 variables are declared together for memory optimisation
        automatically initialized as -> 0 (No quorum by default)
    */
    uint8 votingQuorum;
    uint8 winningQuorum;
    uint8 registeredVoters;
    uint8 votersNb;

    // Mandatory events
    event VoterRegistered(address voterAddress);
    event WorkflowStatusChange(WorkflowStatus previousStatus, WorkflowStatus newStatus);
    event ProposalRegistered(uint proposalId);
    event Voted (address voter, uint proposalId);
    // custom events for quorum
    event VotingQuorumEvent(bool reached);
    event WinningQuorumEvent(bool reached);
    event LogBadCall(address user);
    event LogDepot(address user, uint quantity);

    // Modifier
    modifier onlyVoter {
        require(whitelist[msg.sender].isRegistered == true,
            "You are not registered as a voter.");
        _;
    }

    /**
        We have a receive and fallback function to handle case of people sending ether or making wrong calls
        */
    receive() external payable {
        emit LogDepot(msg.sender, msg.value);
    }

    fallback() external {
        emit LogBadCall(msg.sender);
    }

    /**
        These functions are for registered voters only.
        They use a custom modifier onlyVoter.
        You can register proposals or vote depending on the workflow status.
        A voter can register as many proposal as he wants but can only vote once.
    */
    function registerProposal(string calldata _description) external onlyVoter {
        require(currentStatus == WorkflowStatus.ProposalsRegistrationStarted,
            "The proposal registration period is now closed.");
        proposals.push(Proposal(_description, 0));
        emit ProposalRegistered(proposals.length - 1);
    }

    function voteForProposal(uint _propId) external onlyVoter {
        require(currentStatus == WorkflowStatus.VotingSessionStarted,
            "The voting period is now closed.");
        require(_propId < proposals.length,
            "This proposal does not exists. Please vote again.");
        require(whitelist[msg.sender].hasVoted == false,
            "You have already voted. Cannot vote a second time.");
        proposals[_propId].voteCount ++;
        whitelist[msg.sender].votedProposalId = _propId;
        whitelist[msg.sender].hasVoted = true;
        votersNb ++;
        emit Voted(msg.sender, _propId);
    }

    /**
        These functions are for admin management, therefore they have the modifier onlyOwner.
        The first one add voters to the whitelist while the following four handle the workflow.
        For convenience, we decided to handle the last step of the workflow automatically.
        This would have to be confirmed with Po in real situation.
        The last two are for quorum settlement.
    */
    function addToWhitelist(address _address) external onlyOwner {
        require(currentStatus == WorkflowStatus.RegisteringVoters,
            "Whitelist registration period is closed.");
        require(whitelist[_address].isRegistered == false,
            "Voter is already registered.");
        whitelist[_address] = Voter(true, false, 0);
        registeredVoters ++;
        emit VoterRegistered(_address);
    }

    function startProposalRegistration() external onlyOwner {
        require(currentStatus == WorkflowStatus.RegisteringVoters,
            "Can not start proposal registration in this workflow phase.");
        proposals.push(Proposal("Vote Blanc", 0));
        currentStatus = WorkflowStatus.ProposalsRegistrationStarted;
        emit WorkflowStatusChange(WorkflowStatus.RegisteringVoters,
            WorkflowStatus.ProposalsRegistrationStarted);
    }

    // Workflow management
    function endProposalRegistration() external onlyOwner {
        require(currentStatus == WorkflowStatus.ProposalsRegistrationStarted,
            "Can not end proposal registration in this workflow phase.");
        require(proposals.length > 1,
            "You need at least one proposal to continue the workflow.");
        currentStatus = WorkflowStatus.ProposalsRegistrationEnded;
        emit WorkflowStatusChange(WorkflowStatus.ProposalsRegistrationStarted,
            WorkflowStatus.ProposalsRegistrationEnded);
    }

    function startVotingSession() external onlyOwner {
        require(currentStatus == WorkflowStatus.ProposalsRegistrationEnded,
            "Can not start voting session in this workflow phase.");
        currentStatus = WorkflowStatus.VotingSessionStarted;
        emit WorkflowStatusChange(WorkflowStatus.ProposalsRegistrationEnded,
            WorkflowStatus.VotingSessionStarted);
    }

    function endVotingSession() external onlyOwner {
        require(currentStatus == WorkflowStatus.VotingSessionStarted,
            "Can not end voting session in this workflow phase.");
        currentStatus = WorkflowStatus.VotingSessionEnded;
        emit WorkflowStatusChange(WorkflowStatus.VotingSessionStarted,
            WorkflowStatus.VotingSessionEnded);
        doCounts();
    }

    // Quorum settlement
    function setVotingQuorum(uint8 _vq) external onlyOwner {
        require(currentStatus == WorkflowStatus.ProposalsRegistrationEnded,
            "Can not set quorum in this workflow phase.");
        require(_vq <= 100, "Quorum must be expressed in percentage. Value must be between 0 and 100.");
        votingQuorum = _vq;
    }

    function setWiningQuorum(uint8 _wq) external onlyOwner {
        require(currentStatus == WorkflowStatus.ProposalsRegistrationEnded,
            "Can not set quorum in this workflow phase.");
        require(_wq <= 100, "Quorum must be expressed in percentage. Value must be between 0 and 100.");
        winningQuorum = _wq;
    }

    /**
        This function is visible for everyone.
        View function must be after other external functions as per solidity style guide.
    */
    function getWinner() external view returns (string[] memory){
        require(currentStatus == WorkflowStatus.VotesTallied,
            "Can not show winning proposal before closing the counts.");

        return winningProposalsDescriptions;
    }

    /**
        These functions are called internally.
        When the admin end the voting session, it triggers the function "doCounts".
        This function :
        - determines the winning proposal ids.
        - Check if the quorum are reached.
        - and then trigger the function "closeCounts".
        The last step of the workflow is then done automatically.
    */
    function doCounts() private {

        uint _highestVote;

        for (uint8 _i = 0; _i < proposals.length; _i++) {
            if (proposals[_i].voteCount > _highestVote) {
                _highestVote = proposals[_i].voteCount;
            }
        }

        for (uint _j = 0; _j < proposals.length; _j++) {
            if (proposals[_j].voteCount == _highestVote) {
                winningProposalIds.push(_j);
            }
        }

        // This will be remove later and dealt with in dApp
        for (uint8 _k = 0; _k < winningProposalIds.length; _k ++) {
            winningProposalsDescriptions.push(proposals[winningProposalIds[_k]].description);
        }

        // We will check the quorum and send related events to be handled in frontend.
        checkQuorum(_highestVote);

        // We follow through next workflow step.
        closeCounts();
    }

    function closeCounts() private {
        require(currentStatus == WorkflowStatus.VotingSessionEnded,
            "Can not close counts in this workflow phase.");
        currentStatus = WorkflowStatus.VotesTallied;
        emit WorkflowStatusChange(WorkflowStatus.VotingSessionEnded,
            WorkflowStatus.VotesTallied);
    }

    function checkQuorum(uint _highestVote) private  {
        bool _votingQuorumReached = 100 * votersNb / registeredVoters >= votingQuorum;
        emit VotingQuorumEvent(_votingQuorumReached);
        bool _winningQuorumReached = 100 * _highestVote / votersNb >= winningQuorum;
        emit WinningQuorumEvent(_winningQuorumReached);
    }
}