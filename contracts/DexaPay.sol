// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./DexaBase.sol";

enum RequestType {
    Wallet,
    Email
}

enum RequestStatus {
    Pending,
    Rejected,
    Fulfilled
}

struct TokenBalance {
    address tokenAddress;
    uint256 balance;
}

struct User {
    string username;
    string name;
    address payable wallet;
    string payId;
    string email;
    uint256 createdAt;
    uint256 updatedAt;
}

struct RequestPayment {
    address sender;
    address recipient;
    address token;
    uint256 amount;
    uint256 fee;
    bytes email;
    string remark;
    uint256 createdAt;
    uint256 expiresAt;
    RequestType requestType;
    RequestStatus status;
    bool isRequesting;
    bytes paymentCode;
}

contract DexaPay is DexaBase {
    event TokenEnlisted(address indexed tokenAddress);
    event TokenDelisted(address indexed tokenAddress);
    event UserRegistered(address indexed user, string username);
    event Transfer(
        address indexed from,
        address indexed to,
        uint256 amount,
        uint256 timestamp
    );
    event Deposit(
        address indexed from,
        address indexed to,
        uint256 amount,
        address token,
        uint256 timestamp
    );
    event PaymentSent(
        bytes paymentCode,
        address from,
        bytes email,
        uint256 amount
    );
    event PaymentClaimed(
        bytes paymentCode,
        bytes email,
        address indexed to,
        uint256 amount
    );
    event RequestSent(
        bytes paymentCode,
        address from,
        bytes to,
        uint256 amount,
        uint256 expiresAt
    );

    uint256 public txCount;
    uint256 private reqCount;
    address[] private _tokenAddresses;
    address[] private _userAddresses;

    bytes32 private DOMAIN_SEPARATOR;
    bytes32 private CLAIMBY_EMAIL_TYPEHASH;

    mapping(address => User) private _users;
    mapping(string => address) private _payIds;
    mapping(string => address) private _usernames;
    mapping(bytes => uint256) private _paymentCodes; // Payment codes mapping to request Ids
    mapping(address => bool) private _enlistedTokens;
    mapping(address => uint256) private _baseBalances; // User address to base balance in wei
    mapping(address => uint256[]) private _usersRequest; // User requests array
    mapping(uint256 => RequestPayment) private _requests;
    mapping(uint256 => Transaction) private _transactions;
    mapping(bytes => mapping(uint256 => address)) private _emailToReq;
    mapping(bytes => mapping(address => uint256)) private _emailBalances; // Email => Token address => amount sent
    mapping(address => mapping(address => uint256)) private _tokenBalances; // User address to token address to token balance in wei

    modifier onlyEnlistedToken(address tokenAddress) {
        if (tokenAddress != address(0)) {
            require(
                _enlistedTokens[tokenAddress] == true,
                _initError(ERROR_NOT_FOUND)
            );
        }
        _;
    }

    function init_dexa_pay(address _admin) public initializer {
        __AccessControl_init();
        init_dexa_base(_admin);
        _grantRole(MODERATOR_ROLE, msg.sender);
        CLAIMBY_EMAIL_TYPEHASH = keccak256(
            "UserData(bytes email,address token,bytes paymentCode,address user)"
        );
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256(
                    bytes(
                        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                    )
                ),
                keccak256(bytes("DexaPay")),
                keccak256(bytes("1")),
                block.chainid,
                address(this)
            )
        );
    }

    function init_roles(
        address dexaBill
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(DEXA_PAY_ROLE, address(this));
        _grantRole(DEXA_BILL_ROLE, dexaBill);
    }

    function registerUser(
        string memory username,
        string memory displayName,
        string memory payId
    ) public {
        string memory name = toLower(username);
        require(
            _users[msg.sender].wallet == address(0) &&
                _usernames[name] == address(0) &&
                _payIds[payId] == address(0),
            _initError(ERROR_DUPLICATE_RESOURCE)
        );
        require(
            bytes(displayName).length > 0 &&
                bytes(username).length > 0 &&
                bytes(payId).length >= 8,
            _initError(ERROR_INVALID_STRING)
        );

        User storage user = _users[msg.sender];
        user.name = displayName;
        user.username = name;
        user.payId = payId;
        user.wallet = payable(msg.sender);
        user.createdAt = block.timestamp;
        _usernames[name] = msg.sender;
        _payIds[payId] = msg.sender;

        _userAddresses.push(msg.sender);
        _grantRole(USER_ROLE, msg.sender);
        emit UserRegistered(msg.sender, username);
    }

    function findUser(address key) public view returns (User memory) {
        return _users[key];
    }

    function getUserByName(
        string memory username
    ) public view returns (User memory) {
        return _users[_usernames[toLower(username)]];
    }

    function isNameFree(string memory username) public view returns (bool) {
        return _usernames[toLower(username)] == address(0);
    }

    function getBalances(
        address user
    ) public view returns (TokenBalance[] memory) {
        TokenBalance[] memory balances = new TokenBalance[](
            _tokenAddresses.length + 1
        );
        for (uint256 i = 0; i < _tokenAddresses.length; i++) {
            address tokenAddress = _tokenAddresses[i];
            balances[i] = TokenBalance({
                tokenAddress: tokenAddress,
                balance: _tokenBalances[user][tokenAddress]
            });
        }
        balances[_tokenAddresses.length] = TokenBalance({
            tokenAddress: address(0),
            balance: _baseBalances[user]
        });

        return balances;
    }

    function getUserRequests() public view returns (RequestPayment[] memory) {
        uint256 arrLength = _usersRequest[msg.sender].length;
        RequestPayment[] memory requests = new RequestPayment[](arrLength);
        for (uint i; i < arrLength; i++) {
            uint256 reqId = _usersRequest[msg.sender][i];
            requests[i] = _requests[reqId];
        }
        return requests;
    }

    function getUserTransactions() public view returns (Transaction[] memory) {
        uint256 userTxCount;
        for (uint256 i; i < txCount; i++) {
            if (
                _transactions[i].txFrom == msg.sender ||
                _transactions[i].txTo == msg.sender
            ) {
                userTxCount++;
            }
        }

        Transaction[] memory userTx = new Transaction[](userTxCount);
        uint256 txIndex;
        for (uint256 i; i < txCount; i++) {
            if (
                _transactions[i].txFrom == msg.sender ||
                _transactions[i].txTo == msg.sender
            ) {
                userTx[txIndex] = _transactions[i];
                txIndex++;
            }
        }

        return userTx;
    }

    function deposit(
        uint256 _amount,
        address tokenAddress
    ) public payable onlyRole(USER_ROLE) onlyEnlistedToken(tokenAddress) {
        uint256 amount;
        if (tokenAddress == address(0)) {
            require(msg.value > 0, _initError(ERROR_INVALID_PRICE));
            _baseBalances[msg.sender] += msg.value;
            amount = msg.value;
        } else {
            ERC20Upgradeable token = ERC20Upgradeable(tokenAddress);
            require(
                token.balanceOf(msg.sender) >= _amount && _amount > 0,
                _initError(ERROR_INVALID_PRICE)
            );
            require(
                token.transferFrom(msg.sender, address(this), _amount),
                _initError(ERROR_PROCESS_FAILED)
            );
            _tokenBalances[msg.sender][tokenAddress] += _amount;
            amount = _amount;
        }

        logTransaction(
            msg.sender,
            address(this),
            tokenAddress,
            amount,
            0,
            TransactionType.Deposit,
            ""
        );
        emit Deposit(
            msg.sender,
            address(this),
            amount,
            tokenAddress,
            block.timestamp
        );
    }

    function transferExternal(
        address to,
        uint256 amount,
        address tokenAddress,
        string memory remark
    ) public nonReentrant onlyRole(USER_ROLE) onlyEnlistedToken(tokenAddress) {
        if (tokenAddress == address(0)) {
            require(
                _baseBalances[msg.sender] >= amount,
                _initError(ERROR_INVALID_PRICE)
            );
            _baseBalances[msg.sender] -= amount;
            payable(to).transfer(amount);
        } else {
            require(
                _tokenBalances[msg.sender][tokenAddress] >= amount,
                _initError(ERROR_INVALID_PRICE)
            );
            _tokenBalances[msg.sender][tokenAddress] -= amount;
            ERC20Upgradeable token = ERC20Upgradeable(tokenAddress);
            require(
                token.transfer(to, amount),
                _initError(ERROR_PROCESS_FAILED)
            );
        }

        address sender = msg.sender == to ? address(this) : msg.sender;

        logTransaction(
            sender,
            to,
            tokenAddress,
            amount,
            0,
            TransactionType.Withdraw,
            remark
        );
        emit Transfer(msg.sender, to, amount, block.timestamp);
    }

    function transferInternal(
        address to,
        uint amount,
        address token,
        string memory remark
    ) public nonReentrant onlyRole(USER_ROLE) onlyEnlistedToken(token) {
        require(msg.sender != to, _initError(ERROR_UNAUTHORIZED_ACCESS));

        if (token == address(0)) {
            require(
                _baseBalances[msg.sender] >= amount,
                _initError(ERROR_INVALID_PRICE)
            );
            _baseBalances[msg.sender] -= amount;
            _baseBalances[to] += amount;
        } else {
            require(
                _tokenBalances[msg.sender][token] >= amount,
                _initError(ERROR_INVALID_PRICE)
            );
            _tokenBalances[msg.sender][token] -= amount;
            _tokenBalances[to][token] += amount;
        }

        logTransaction(
            msg.sender,
            to,
            token,
            amount,
            0,
            TransactionType.Transfer,
            remark
        );
        emit Transfer(msg.sender, to, amount, block.timestamp);
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
        _transactions[txCount] = Transaction(
            txCount,
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
        return txCount;
    }

    function createTx(
        address from,
        address to,
        address token,
        uint256 amount,
        uint256 fee,
        TransactionType txType,
        string memory remark
    ) external {
        if (!hasRole(DEXA_PAY_ROLE, msg.sender)) {
            revert(_initError(ERROR_UNAUTHORIZED_ACCESS));
        }
        logTransaction(from, to, token, amount, fee, txType, remark);
    }

    function payByEmail(
        uint256 amount,
        bytes memory email,
        string memory remark,
        address token,
        bytes memory code
    ) public onlyRole(USER_ROLE) onlyEnlistedToken(token) {
        require(amount > 0, _initError(ERROR_INVALID_PRICE));
        require(_paymentCodes[code] == 0, _initError(ERROR_DUPLICATE_RESOURCE));
        // Charge fee here
        if (token == address(0)) {
            require(
                _baseBalances[msg.sender] >= amount && amount > 0,
                _initError(ERROR_INVALID_PRICE)
            );
            _baseBalances[msg.sender] -= amount;
            _emailBalances[email][token] += amount;
        } else {
            require(
                _tokenBalances[msg.sender][token] >= amount && amount > 0,
                _initError(ERROR_INVALID_PRICE)
            );
            _tokenBalances[msg.sender][token] -= amount;
            _emailBalances[email][token] += amount;
        }

        initRequest(
            amount,
            token,
            msg.sender,
            email,
            remark,
            RequestType.Email,
            RequestStatus.Pending,
            false,
            code
        );
        _paymentCodes[code] = reqCount;
        _usersRequest[msg.sender].push(reqCount);

        reqCount++;
        emit PaymentSent(code, msg.sender, email, amount);
    }

    function claimEmailBalance(
        bytes memory email,
        address token,
        bytes memory paymentCode,
        bytes memory signature
    ) public onlyEnlistedToken(token) {
        bytes32 messageHash = keccak256(
            abi.encode(
                CLAIMBY_EMAIL_TYPEHASH,
                keccak256(email),
                token,
                keccak256(paymentCode),
                msg.sender
            )
        );
        bytes32 ethSignedMessageHash = getEthSignedMessageHash(
            messageHash,
            DOMAIN_SEPARATOR
        );
        address signer = recoverSigner(ethSignedMessageHash, signature);
        require(
            hasRole(DEFAULT_ADMIN_ROLE, signer) == true,
            _initError(ERROR_UNAUTHORIZED_ACCESS)
        );

        uint256 reqId = _paymentCodes[paymentCode];
        RequestPayment memory req = _requests[reqId];

        require(
            req.status == RequestStatus.Pending,
            _initError(ERROR_NOT_FOUND)
        );

        require(
            _emailToReq[email][reqId] == msg.sender,
            _initError(ERROR_UNAUTHORIZED_ACCESS)
        );

        uint256 amount = _emailBalances[email][token];
        require(amount >= req.amount, _initError(ERROR_INVALID_PRICE));

        _emailBalances[email][token] -= req.amount;
        _requests[reqId].status = RequestStatus.Fulfilled;
        _requests[reqId].recipient = msg.sender;

        token == address(0)
            ? _baseBalances[msg.sender] += req.amount
            : _tokenBalances[msg.sender][token] += req.amount;

        emit PaymentClaimed(paymentCode, email, msg.sender, req.amount);
    }

    function requestPayment(
        address token,
        uint256 amount,
        bytes memory email,
        string memory remark,
        bytes memory code
    ) public onlyEnlistedToken(token) onlyRole(USER_ROLE) {
        require(amount > 0, _initError(ERROR_INVALID_PRICE));
        require(_paymentCodes[code] == 0, _initError(ERROR_DUPLICATE_RESOURCE));

        initRequest(
            amount,
            token,
            msg.sender,
            email,
            remark,
            RequestType.Email,
            RequestStatus.Pending,
            true,
            code
        );
        uint256 expiresAt = block.timestamp + 3 days;
        _requests[reqCount].expiresAt = expiresAt;
        _paymentCodes[code] = reqCount;
        _usersRequest[msg.sender].push(reqCount);

        reqCount++;
        emit RequestSent(code, msg.sender, email, amount, expiresAt);
    }

    function fulfillRequest(
        address token,
        bytes memory code
    ) public payable onlyEnlistedToken(token) {
        uint256 reqId = _paymentCodes[code];
        RequestPayment storage req = _requests[reqId];

        require(
            req.status == RequestStatus.Pending,
            _initError(ERROR_NOT_FOUND)
        );

        if (token == address(0)) {
            require(msg.value >= req.amount, _initError(ERROR_INVALID_PRICE));
            _baseBalances[req.sender] += req.amount;
        } else {
            ERC20Upgradeable ercToken = ERC20Upgradeable(token);
            require(
                ercToken.balanceOf(msg.sender) >= req.amount,
                _initError(ERROR_INVALID_PRICE)
            );
            require(
                ercToken.transferFrom(msg.sender, address(this), req.amount),
                _initError(ERROR_PROCESS_FAILED)
            );
            _tokenBalances[req.sender][token] += req.amount;
        }

        _usersRequest[msg.sender].push(reqId);
        req.status = RequestStatus.Fulfilled;
        emit PaymentSent(code, msg.sender, req.email, req.amount);
    }

    function linkUserEmailBalance(
        bytes memory email,
        address owner,
        bytes memory paymentCode
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 reqId = _paymentCodes[paymentCode];
        bytes memory reqEmail = _requests[reqId].email;
        require(
            keccak256(abi.encodePacked(reqEmail)) ==
                keccak256(abi.encodePacked(email)),
            _initError(ERROR_NOT_FOUND)
        );
        if (_emailToReq[email][reqId] == address(0)) {
            _emailToReq[email][reqId] = owner;
            _usersRequest[owner].push(reqId);
        }
    }

    function initRequest(
        uint256 amount,
        address token,
        address sender,
        bytes memory email,
        string memory remark,
        RequestType reqType,
        RequestStatus status,
        bool requesting,
        bytes memory code
    ) private {
        RequestPayment storage req = _requests[reqCount];
        req.amount = amount;
        req.token = token;
        req.sender = sender;
        req.email = email;
        req.remark = remark;
        req.requestType = reqType;
        req.createdAt = block.timestamp;
        req.status = status;
        req.isRequesting = requesting;
        req.paymentCode = code;
    }

    function isTokenEnlisted(address token) public view returns (bool) {
        return _enlistedTokens[token] == true;
    }

    function batchEnlistTokens(
        address[] memory tokenAddress
    ) public onlyRole(MODERATOR_ROLE) {
        for (uint256 i = 0; i < tokenAddress.length; i++) {
            if (tokenAddress[i] != address(0)) {
                _enlistedTokens[tokenAddress[i]] = true;
                _tokenAddresses.push(tokenAddress[i]);
                emit TokenEnlisted(tokenAddress[i]);
            }
        }
    }

    function batchDelistTokens(
        address[] memory tokenAddress
    ) public onlyRole(MODERATOR_ROLE) {
        for (uint256 i = 0; i < tokenAddress.length; i++) {
            if (tokenAddress[i] != address(0)) {
                _enlistedTokens[tokenAddress[i]] = false;
                emit TokenDelisted(tokenAddress[i]);
            }
        }
    }

    function getEthSignedMessageHash(
        bytes32 messageHash,
        bytes32 domainSeparator
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encodePacked("\x19\x01", domainSeparator, messageHash)
            );
    }

    function recoverSigner(
        bytes32 ethSignedMessageHash,
        bytes memory signature
    ) internal pure returns (address) {
        (bytes32 r, bytes32 s, uint8 v) = splitSignature(signature);
        return ecrecover(ethSignedMessageHash, v, r, s);
    }

    function splitSignature(
        bytes memory sig
    ) internal pure returns (bytes32 r, bytes32 s, uint8 v) {
        require(sig.length == 65, _initError(ERROR_INVALID_STRING));

        assembly {
            r := mload(add(sig, 32))
            s := mload(add(sig, 64))
            v := byte(0, mload(add(sig, 96)))
        }
    }
}
