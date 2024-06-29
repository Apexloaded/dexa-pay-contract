// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./DexaPay.sol";

enum VisibilityType {
    Public,
    Private
}

enum ParticipantType {
    Single,
    Multiple
}

enum BillStatus {
    Active,
    Completed
}

struct Bill {
    uint256 id;
    string billId;
    string billUrl;
    string title;
    string description;
    uint256 amount;
    uint256 balance;
    address creator;
    address recipient;
    address billToken;
    uint256 createdAt;
    uint256 expiresAt;
    bool isRecurring;
    bool isFixedAmount;
    address[] visibleTo;
    VisibilityType visibility;
    BillStatus status;
    uint256 realisedAmount;
    address[] participants;
    ParticipantType participantType;
}

struct Participants {
    address user;
    uint256 amount;
    uint256 count;
    uint256 updatedAt;
}

contract DexaBill is DexaBase {
    event BillCreated(address indexed creator, uint256 indexed id);
    event BillFunded(
        address indexed funder,
        uint256 indexed id,
        uint256 amount
    );
    event BillRemitted(
        address indexed recipient,
        uint256 indexed id,
        uint256 amount
    );

    uint256 public txCount;
    uint256 public billCount;
    DexaPay private _dexaPay;
    string private dexaBaseURI;
    uint256[] public bills;

    mapping(uint256 => Bill) private _bill;
    mapping(string => uint256) private _billIds;
    mapping(uint256 => uint256[]) private _billTxns;
    mapping(address => uint256[]) private _userBills;
    mapping(uint256 => Transaction) private _transactions;
    mapping(uint256 => uint256[]) private _billRemittances;
    mapping(uint256 => mapping(address => Participants)) private _participants;

    modifier onlyUser() {
        if (!_dexaPay.hasRole(USER_ROLE, msg.sender)) {
            revert(_initError(ERROR_UNAUTHORIZED_ACCESS));
        }
        _;
    }

    modifier onlyAllowedTokens(address token) {
        if (!_dexaPay.isTokenEnlisted(token)) {
            revert(_initError(ERROR_NOT_FOUND));
        }
        _;
    }

    modifier onlyBillOwner(uint256 id) {
        require(
            _bill[id].creator == msg.sender,
            _initError(ERROR_UNAUTHORIZED_ACCESS)
        );
        _;
    }

    function init_dexa_bill(
        address _admin,
        address dexaPay,
        string memory baseUrl
    ) public initializer {
        __AccessControl_init();
        init_dexa_base(_admin);
        _grantRole(MODERATOR_ROLE, msg.sender);
        _dexaPay = DexaPay(dexaPay);
        dexaBaseURI = baseUrl;
    }

    function init_roles(address dexaPay) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(DEXA_BILL_ROLE, address(this));
        _grantRole(DEXA_PAY_ROLE, dexaPay);
    }

    function createBill(
        string memory id,
        string memory title,
        string memory description,
        uint256 amount,
        address billToken,
        ParticipantType participantType,
        bool isFixedAmount
    ) public onlyUser onlyAllowedTokens(billToken) {
        string memory billId = toLower(id);
        require(_billIds[billId] == 0, _initError(ERROR_DUPLICATE_RESOURCE));
        require(
            bytes(billId).length > 0 &&
                bytes(title).length > 10 &&
                bytes(description).length >= 20,
            _initError(ERROR_INVALID_STRING)
        );
        if (isFixedAmount && amount < 1) {
            revert(_initError(ERROR_INVALID_PRICE));
        }

        Bill storage bill = _bill[billCount];
        bill.id = billCount;
        bill.title = title;
        bill.description = description;
        bill.billId = billId;
        bill.amount = amount;
        bill.visibility = VisibilityType.Public;
        bill.billToken = billToken;
        bill.participantType = participantType;
        bill.isFixedAmount = isFixedAmount;
        bill.creator = msg.sender;
        bill.createdAt = block.timestamp;
        bill.status = BillStatus.Active;

        _billIds[billId] = billCount;
        _userBills[msg.sender].push(billCount);
        bills.push(billCount);
        billCount++;
    }

    function getAllUsersBills() public view returns (Bill[] memory) {
        uint256[] memory tempBills = _userBills[msg.sender];
        Bill[] memory userBills = new Bill[](tempBills.length);
        for (uint256 i; i < tempBills.length; i++) {
            uint256 id = tempBills[i];
            userBills[i] = makeBill(id);
        }
        return userBills;
    }

    function getBill(string memory billId) public view returns (Bill memory) {
        uint256 id = _billIds[billId];
        return makeBill(id);
    }

    function getBillTransactions(
        uint256 billId
    ) public view returns (Transaction[] memory) {
        uint256[] memory tempTxns = _billTxns[billId];
        Transaction[] memory billTxns = new Transaction[](tempTxns.length);
        for (uint256 i; i < tempTxns.length; i++) {
            uint256 txId = tempTxns[i];
            billTxns[i] = _transactions[txId];
        }
        return billTxns;
    }

    function getBillParticipants(
        uint256 billId
    ) public view returns (Participants[] memory) {
        address[] memory tempParticipants = _bill[billId].participants;
        Participants[] memory participants = new Participants[](
            tempParticipants.length
        );
        for (uint256 i; i < tempParticipants.length; i++) {
            address userAddr = tempParticipants[i];
            participants[i] = _participants[billId][userAddr];
        }
        return participants;
    }

    function getBillRemittances(
        uint256 billId
    ) public view returns (Transaction[] memory) {
        uint256[] memory tempTxns = _billRemittances[billId];
        Transaction[] memory billTxns = new Transaction[](tempTxns.length);
        for (uint256 i; i < tempTxns.length; i++) {
            uint256 txId = tempTxns[i];
            billTxns[i] = _transactions[txId];
        }
        return billTxns;
    }

    function makeBill(uint256 id) private view returns (Bill memory) {
        string memory billUrl = _generateUrl("/i/bills/", _bill[id].billId);
        return
            Bill(
                _bill[id].id,
                _bill[id].billId,
                billUrl,
                _bill[id].title,
                _bill[id].description,
                _bill[id].amount,
                _bill[id].balance,
                _bill[id].creator,
                _bill[id].recipient,
                _bill[id].billToken,
                _bill[id].createdAt,
                _bill[id].expiresAt,
                _bill[id].isRecurring,
                _bill[id].isFixedAmount,
                _bill[id].visibleTo,
                _bill[id].visibility,
                _bill[id].status,
                _bill[id].realisedAmount,
                _bill[id].participants,
                _bill[id].participantType
            );
    }

    function closeBill(uint256 billId) public onlyBillOwner(billId) {
        _bill[billId].status = BillStatus.Completed;
    }

    function remiteBill(
        address recipient,
        uint256 amount,
        uint256 id
    ) external onlyBillOwner(id) nonReentrant {
        Bill memory bill = _bill[id];
        require(bill.balance >= amount, _initError(ERROR_INVALID_PRICE));

        _bill[id].balance -= amount;
        if (bill.billToken == address(0)) {
            payable(recipient).transfer(amount);
        } else {
            require(
                _bill[id].balance >= amount,
                _initError(ERROR_INVALID_PRICE)
            );
            ERC20Upgradeable token = ERC20Upgradeable(bill.billToken);
            require(
                token.transfer(recipient, amount),
                _initError(ERROR_PROCESS_FAILED)
            );
        }

        uint256 txId = logTransaction(
            address(this),
            recipient,
            bill.billToken,
            amount,
            0,
            TransactionType.RemiteBill,
            ""
        );
        _billTxns[id].push(txId);
        _billRemittances[id].push(txId);
        emit BillRemitted(recipient, id, amount);
    }

    function fundBill(
        uint256 id,
        address token,
        uint256 _amount
    ) public payable nonReentrant {
        Bill memory bill = _bill[id];
        require(
            bill.status == BillStatus.Active,
            _initError(ERROR_EXPIRED_RESOURCE)
        );

        uint256 amount = token == address(0) ? msg.value : _amount;
        if (bill.isFixedAmount) {
            require(amount >= bill.amount, _initError(ERROR_INVALID_PRICE));
        }

        if (bill.participantType == ParticipantType.Single) {
            bill.status = BillStatus.Completed;
        }

        if (_participants[id][msg.sender].user == address(0)) {
            _bill[id].participants.push(msg.sender);
            uint256 count = _participants[id][msg.sender].count++;
            _participants[id][msg.sender] = Participants(
                msg.sender,
                amount,
                count,
                block.timestamp
            );
        } else {
            _participants[id][msg.sender].count++;
            _participants[id][msg.sender].amount += amount;
            _participants[id][msg.sender].updatedAt = block.timestamp;
        }

        if (bill.billToken == address(0)) {
            require(
                amount > 0 && amount >= bill.amount,
                _initError(ERROR_INVALID_PRICE)
            );
        } else {
            ERC20Upgradeable billToken = ERC20Upgradeable(bill.billToken);
            require(
                billToken.balanceOf(msg.sender) >= amount && amount > 0,
                _initError(ERROR_INVALID_PRICE)
            );
            require(
                billToken.transferFrom(msg.sender, address(this), amount),
                _initError(ERROR_PROCESS_FAILED)
            );
        }

        _bill[id].realisedAmount += amount;
        _bill[id].balance += amount;

        uint256 txId = logTransaction(
            msg.sender,
            _bill[id].creator,
            token,
            amount,
            0,
            TransactionType.FundBill,
            ""
        );
        _billTxns[id].push(txId);
        emit BillFunded(msg.sender, id, amount);
    }

    function logTransaction(
        address from,
        address to,
        address token,
        uint256 amount,
        uint256 fee,
        TransactionType txType,
        string memory remark
    ) private returns (uint256) {
        uint256 oldId = txCount;
        _transactions[oldId] = Transaction(
            oldId,
            txType,
            payable(from),
            payable(to),
            amount,
            fee,
            block.timestamp,
            token,
            remark
        );
        txCount++;
        return oldId;
    }

    function _generateUrl(
        string memory startPath,
        string memory endPath
    ) internal view returns (string memory) {
        string memory url = string.concat(dexaBaseURI, startPath, endPath);
        return url;
    }
}
