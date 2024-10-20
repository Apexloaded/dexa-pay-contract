// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Base, ERC20Upgradeable} from "./Base.sol";
import {Gateway} from "./Gateway.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

// Uncomment this line to use console.log
import "hardhat/console.sol";

contract Taxes is Base {
    using Math for uint256;

    struct MemberInfo {
        bool isMember;
        uint256 lastContributionDate;
        uint256 totalContributed;
        uint256 strikes;
    }

    struct Cooperative {
        string name;
        string description;
        string logo;
        address creator;
        address[] members;
        uint256 contributionAmount;
        uint256 contributionPeriod;
        uint256 nextContributionDate;
        uint256 totalContributions;
        uint256 currentRound;
        PayoutScheme payoutScheme;
    }

    struct Proposal {
        string description;
        uint256 forVotes;
        uint256 againstVotes;
        uint256 endTime;
        bool executed;
        mapping(address => bool) hasVoted;
    }

    enum PayoutScheme {
        ROTATING,
        NEED_BASED,
        RANDOM
    }

    uint256 public constant MAX_STRIKES = 3;
    uint256 public constant VOTING_PERIOD = 3 days;

    Gateway private _gateway;
    uint256 private _cooperativeIds;
    uint256 private _proposalIds;
    uint256 public feePercentage;

    mapping(address => uint256) private accumulatedFees;
    mapping(uint256 => address) contributionToken;
    mapping(uint256 => mapping(address => bool)) isMember;
    mapping(uint256 => mapping(address => uint256)) lastContributionDate;
    mapping(uint256 => mapping(address => uint256)) totalContributed;
    mapping(uint256 => mapping(uint256 => address)) payoutOrder;
    mapping(uint256 => mapping(address => uint256)) strikes;

    mapping(uint256 => Cooperative) public cooperatives;
    mapping(uint256 => Proposal) public proposals;

    event CooperativeCreated(
        uint256 indexed cooperativeId,
        string name,
        address creator
    );
    event MemberJoined(uint256 indexed cooperativeId, address member);
    event ContributionMade(
        uint256 indexed cooperativeId,
        address member,
        uint256 amount
    );
    event PayoutMade(
        uint256 indexed cooperativeId,
        address member,
        uint256 amount
    );
    event ProposalCreated(
        uint256 indexed proposalId,
        uint256 indexed cooperativeId,
        string description
    );
    event Voted(uint256 indexed proposalId, address voter, bool inFavor);
    event ProposalExecuted(uint256 indexed proposalId);
    event MemberProsecuted(
        uint256 indexed cooperativeId,
        address member,
        uint256 strikes
    );
    event MemberBanned(uint256 indexed cooperativeId, address member);
    event FeePercentageUpdated(uint256 newFeePercentage);
    event FeesWithdrawn(address token, uint256 amount);

    modifier onlyCooperativeMember(uint256 _cooperativeId) {
        require(
            isMember[_cooperativeId][msg.sender],
            "Not a member of this cooperative"
        );
        _;
    }

    // modifier onlyAllowedTokens(address token) {
    //     if (!_gateway.isTokenEnlisted(token)) {
    //         revert(_initError(ERROR_NOT_FOUND));
    //     }
    //     _;
    // }

    function initializeTaxes(
        address _admin,
        address gatewayAddress
    ) public initializer {
        init_dexa_base(_admin);
        _gateway = Gateway(gatewayAddress);
        feePercentage = 100; // 1% fee (100 basis points)
    }

    function setFeePercentage(uint256 _newFeePercentage) external onlyOwner {
        require(_newFeePercentage <= 1000, "Fee percentage cannot exceed 10%");
        feePercentage = _newFeePercentage;
        emit FeePercentageUpdated(_newFeePercentage);
    }

    function createCooperative(
        string memory _name,
        string memory _description,
        string memory _logo,
        uint256 _contributionAmount,
        uint256 _contributionPeriod,
        address[] memory _initialMembers,
        address _contributionToken,
        PayoutScheme _payoutScheme
    ) external returns (uint256) {
        require(_contributionAmount > 0, _initError(ERROR_INVALID_PRICE));
        require(_contributionPeriod > 0, _initError(ERROR_INVALID_PERIOD));

        uint256 cooperativeId = _cooperativeIds;
        Cooperative storage newCooperative = cooperatives[cooperativeId];

        newCooperative.name = _name;
        newCooperative.description = _description;
        newCooperative.logo = _logo;
        newCooperative.creator = msg.sender;
        newCooperative.contributionAmount = _contributionAmount;
        newCooperative.contributionPeriod = _contributionPeriod;
        newCooperative.nextContributionDate =
            block.timestamp +
            _contributionPeriod;
        newCooperative.payoutScheme = _payoutScheme;

        contributionToken[cooperativeId] = _contributionToken;

        for (uint256 i = 0; i < _initialMembers.length; i++) {
            address member = _initialMembers[i];
            require(
                !isMember[cooperativeId][member],
                _initError(ERROR_DUPLICATE_RESOURCE)
            );
            newCooperative.members.push(member);
            isMember[cooperativeId][member] = true;
            payoutOrder[cooperativeId][i] = member;
        }

        _cooperativeIds = _cooperativeIds + 1;

        emit CooperativeCreated(cooperativeId, _name, msg.sender);
        return cooperativeId;
    }

    function joinCooperative(uint256 _cooperativeId) external {
        Cooperative storage cooperative = cooperatives[_cooperativeId];
        require(
            !isMember[_cooperativeId][msg.sender],
            _initError(ERROR_DUPLICATE_RESOURCE)
        );

        cooperative.members.push(msg.sender);
        isMember[_cooperativeId][msg.sender] = true;
        payoutOrder[_cooperativeId][cooperative.members.length - 1] = msg
            .sender;

        emit MemberJoined(_cooperativeId, msg.sender);
    }

    function contribute(
        uint256 _cooperativeId
    ) external payable onlyCooperativeMember(_cooperativeId) nonReentrant {
        Cooperative storage cooperative = cooperatives[_cooperativeId];
        require(
            block.timestamp >= cooperative.nextContributionDate,
            _initError(ERROR_INVALID_PERIOD)
        );

        uint256 amount = cooperative.contributionAmount;
        (, uint256 amountMul) = amount.tryMul(feePercentage);
        (, uint256 fee) = amountMul.tryDiv(10000);
        (, uint256 netContribution) = amount.trySub(fee);

        if (contributionToken[_cooperativeId] == address(0)) {
            require(msg.value >= amount, _initError(ERROR_INVALID_PRICE));
            (, uint256 accFees) = accumulatedFees[address(0)].tryAdd(fee);
            accumulatedFees[address(0)] = accFees;
        } else {
            require(msg.value == 0, "ETH not accepted for this cooperative");
            ERC20Upgradeable token = ERC20Upgradeable(contributionToken[_cooperativeId]);
            console.log("Token Balance", token.balanceOf(msg.sender));
            require(
                token.balanceOf(msg.sender) >= amount && amount > 0,
                _initError(ERROR_INVALID_PRICE)
            );
            require(
                token.transferFrom(msg.sender, address(this), amount),
                _initError(ERROR_PROCESS_FAILED)
            );
            (, uint256 accFees) = accumulatedFees[
                contributionToken[_cooperativeId]
            ].tryAdd(fee);
            accumulatedFees[contributionToken[_cooperativeId]] = accFees;
        }

        (, uint256 total) = cooperative.totalContributions.tryAdd(
            netContribution
        );
        cooperative.totalContributions = total;

        lastContributionDate[_cooperativeId][msg.sender] = block.timestamp;
        (, uint256 contributorsTotal) = totalContributed[_cooperativeId][
            msg.sender
        ].tryAdd(amount);
        totalContributed[_cooperativeId][msg.sender] = contributorsTotal;

        emit ContributionMade(_cooperativeId, msg.sender, amount);

        (, uint256 mulValue) = netContribution.tryMul(
            cooperative.members.length
        );
        if (cooperative.totalContributions >= mulValue) {
            _processPayout(_cooperativeId);
        }
    }

    function _processPayout(uint256 _cooperativeId) internal {
        Cooperative storage cooperative = cooperatives[_cooperativeId];
        address payoutMember;

        if (cooperative.payoutScheme == PayoutScheme.ROTATING) {
            payoutMember = payoutOrder[_cooperativeId][
                cooperative.currentRound
            ];
            cooperative.currentRound =
                (cooperative.currentRound + 1) %
                cooperative.members.length;
        } else if (cooperative.payoutScheme == PayoutScheme.NEED_BASED) {
            payoutMember = _selectNeedBasedMember(_cooperativeId);
        } else if (cooperative.payoutScheme == PayoutScheme.RANDOM) {
            payoutMember = _selectRandomMember(_cooperativeId);
        }

        uint256 payoutAmount = cooperative.totalContributions;
        cooperative.totalContributions = 0;
        (, uint256 nextDate) = block.timestamp.tryAdd(
            cooperative.contributionPeriod
        );
        cooperative.nextContributionDate = nextDate;

        if (contributionToken[_cooperativeId] == address(0)) {
            (bool success, ) = payoutMember.call{value: payoutAmount}("");
            require(success, "ETH transfer failed");
        } else {
            ERC20Upgradeable(contributionToken[_cooperativeId]).transfer(
                payoutMember,
                payoutAmount
            );
        }

        emit PayoutMade(_cooperativeId, payoutMember, payoutAmount);
    }

    function _selectNeedBasedMember(
        uint256 _cooperativeId
    ) internal view returns (address) {
        Cooperative storage cooperative = cooperatives[_cooperativeId];
        address needyMember = cooperative.members[0];
        uint256 lowestContribution = totalContributed[_cooperativeId][
            needyMember
        ];

        for (uint256 i = 1; i < cooperative.members.length; i++) {
            address member = cooperative.members[i];
            if (totalContributed[_cooperativeId][member] < lowestContribution) {
                needyMember = member;
                lowestContribution = totalContributed[_cooperativeId][member];
            }
        }

        return needyMember;
    }

    function _selectRandomMember(
        uint256 _cooperativeId
    ) internal view returns (address) {
        Cooperative storage cooperative = cooperatives[_cooperativeId];
        uint256 randomIndex = uint256(
            keccak256(abi.encodePacked(block.timestamp, block.prevrandao))
        ) % cooperative.members.length;
        return cooperative.members[randomIndex];
    }

    function createProposal(
        uint256 _cooperativeId,
        string memory _description
    ) external onlyCooperativeMember(_cooperativeId) {
        uint256 proposalId = _proposalIds;
        Proposal storage newProposal = proposals[proposalId];

        newProposal.description = _description;
        (, uint256 votingPeriod) = block.timestamp.tryAdd(VOTING_PERIOD);
        newProposal.endTime = votingPeriod;

        _proposalIds = _proposalIds + 1;

        emit ProposalCreated(proposalId, _cooperativeId, _description);
    }

    function vote(
        uint256 _proposalId,
        uint256 _cooperativeId,
        bool _inFavor
    ) external onlyCooperativeMember(_cooperativeId) {
        Proposal storage proposal = proposals[_proposalId];
        require(block.timestamp < proposal.endTime, "Voting period has ended");
        require(!proposal.hasVoted[msg.sender], "Already voted");

        if (_inFavor) {
            (, uint256 forVotes) = proposal.forVotes.tryAdd(1);
            proposal.forVotes = forVotes;
        } else {
            (, uint256 againstVotes) = proposal.forVotes.tryAdd(1);
            proposal.againstVotes = againstVotes;
        }

        proposal.hasVoted[msg.sender] = true;

        emit Voted(_proposalId, msg.sender, _inFavor);
    }

    function executeProposal(
        uint256 _proposalId,
        uint256 _cooperativeId
    ) external onlyCooperativeMember(_cooperativeId) {
        Proposal storage proposal = proposals[_proposalId];
        require(block.timestamp >= proposal.endTime, "Voting period not ended");
        require(!proposal.executed, "Proposal already executed");

        proposal.executed = true;

        if (proposal.forVotes > proposal.againstVotes) {
            // Implement the proposal execution logic here
            // This could involve changing cooperative parameters, adding/removing members, etc.
        }

        emit ProposalExecuted(_proposalId);
    }

    function prosecuteMember(
        uint256 _cooperativeId,
        address _member
    ) external onlyCooperativeMember(_cooperativeId) {
        require(
            isMember[_cooperativeId][_member],
            _initError(ERROR_UNAUTHORIZED_ACCESS)
        );

        (, uint256 strikeCount) = strikes[_cooperativeId][_member].tryAdd(1);
        strikes[_cooperativeId][_member] = strikeCount;

        emit MemberProsecuted(
            _cooperativeId,
            _member,
            strikes[_cooperativeId][_member]
        );

        if (strikes[_cooperativeId][_member] >= MAX_STRIKES) {
            _banMember(_cooperativeId, _member);
        }
    }

    function _banMember(uint256 _cooperativeId, address _member) internal {
        Cooperative storage cooperative = cooperatives[_cooperativeId];
        isMember[_cooperativeId][_member] = false;

        // Remove member from the members array
        for (uint256 i = 0; i < cooperative.members.length; i++) {
            if (cooperative.members[i] == _member) {
                cooperative.members[i] = cooperative.members[
                    cooperative.members.length - 1
                ];
                cooperative.members.pop();
                break;
            }
        }

        emit MemberBanned(_cooperativeId, _member);
    }

    function getCooperativeInfo(
        uint256 _cooperativeId
    ) external view returns (Cooperative memory) {
        Cooperative memory cooperative = cooperatives[_cooperativeId];
        return cooperative;
    }

    function getMemberInfo(
        uint256 _cooperativeId,
        address _member
    ) external view returns (MemberInfo memory) {
        return
            MemberInfo({
                isMember: isMember[_cooperativeId][_member],
                lastContributionDate: lastContributionDate[_cooperativeId][
                    _member
                ],
                totalContributed: totalContributed[_cooperativeId][_member],
                strikes: strikes[_cooperativeId][_member]
            });
    }

    function withdrawFees(address _token) external onlyOwner {
        uint256 feeAmount = accumulatedFees[_token];
        require(feeAmount > 0, "No fees to  withdraw");

        accumulatedFees[_token] = 0;
        console.log('Owner', owner());

        if (_token == address(0)) {
            (bool success, ) = owner().call{value: feeAmount}("");
            require(success, "ETH fee withdrawal failed");
        } else {
            ERC20Upgradeable(_token).transfer(owner(), feeAmount);
        }

        emit FeesWithdrawn(_token, feeAmount);
    }

    receive() external payable {}
}
