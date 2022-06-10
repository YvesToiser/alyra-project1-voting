# alyra-project1-voting

This is the first project in the Alyra training "Blockchain developer".
Project #1 : Voting system

### Vote description :

Vote is not secret. Each voter can view the other's vote.
Winner is determined with simple majority. proposal with the higher number of votes win.

### Requirements :
Smart contract must be named : Voting
Smart contract must use last compiler version.
"Admin" is the person who will deploy the smart contract.
Smart contract must import Ownable contract from OpenZeppelin
Smart contract must contains following structs :
    struct Voter {
        bool isRegistered;
        bool hasVoted;
        uint votedProposalId;
    }
    struct Proposal {
        string description;
        uint voteCount;
    }
Smart contract must contain following enum for handling different steps of the vote process:
    enum WorkflowStatus {
        RegisteringVoters,
        ProposalsRegistrationStarted,
        ProposalsRegistrationEnded,
        VotingSessionStarted,
        VotingSessionEnded,
        VotesTallied
    }    
Smart contract must define the following events :
    event VoterRegistered(address voterAddress); 
    event WorkflowStatusChange(WorkflowStatus previousStatus, WorkflowStatus newStatus);
    event ProposalRegistered(uint proposalId);
    event Voted (address voter, uint proposalId);
Smart contract must define a :
    uint winningProposalId (the winning id) 
    or a function getWinner which returns the winner.

### Vote process

Admin register a whitelist with voters Ethereum address.
Admin starts the proposal registration session.
Registered voters can register proposals during this session.
Admin ends the proposal registration session.
Admin starts the voting session.
Voters can vote for their favorite proposal.
Admin ends the voting session.
Admin counts the vote.
Everyone can see the winning proposals.

### Later additions 

"empty" vote must be possible. (We register it automatically as proposal #0)
Admin can specify minimum quorum for vote validation.
votingQuorum represents the percentage of registered voters who actually voted.
(Number of votes / number of registered voters)
winningQuorum represents the percentage of votes received by the winning proposal compared to number of votes.
(Number of votes for winning proposal / number of votes)
These 2 values are by default 0. So if the admin do no set the quorum, the vote is automatically valid.
These values must be expressed in percentage. Ex for 50% -> input 50.
The admin can set this quorum during the workflow status : endProposalRegistration (before the beginning of the vote)