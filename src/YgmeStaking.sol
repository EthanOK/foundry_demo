// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

abstract contract YgmeStakingDomain {
    struct StakingData {
        address owner;
        bool stakedState;
        uint128 startTime;
        uint128 endTime;
    }

    // Multi Call
    struct Call {
        address target;
        bytes callData;
    }

    event Staking(
        address indexed account,
        uint256 indexed tokenId,
        address indexed nftContract,
        uint256 startTime,
        uint256 endTime,
        uint256 pledgeType
    );

    event WithdrawERC20(uint256 orderId, address account, uint256 amount);
}

contract YgmeStaking is
    YgmeStakingDomain,
    Pausable,
    Ownable,
    ERC721Holder,
    ReentrancyGuard
{
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;

    modifier onlyOperator() {
        require(operator[_msgSender()], "not operator");
        _;
    }

    uint64[3] private stakingPeriods;

    IERC721 public immutable ygme;

    IERC20 public immutable ygio;

    address private withdrawSigner;

    mapping(uint256 => StakingData) public stakingDatas;

    mapping(address => uint256[]) private stakingTokenIds;

    mapping(uint256 => bool) public orderIsInvalid;

    mapping(address => bool) public operator;

    uint128 public accountTotal;

    uint128 public ygmeTotal;

    // TODO: _periods
    constructor(address _ygme, address _ygio, address _withdrawSigner) {
        ygme = IERC721(_ygme);
        ygio = IERC20(_ygio);
        withdrawSigner = _withdrawSigner;
        stakingPeriods = [60, 120, 360];
    }

    function setPause() external onlyOwner {
        if (!paused()) {
            _pause();
        } else {
            _unpause();
        }
    }

    function setStakingPeriods(uint64[3] calldata _periods) external onlyOwner {
        stakingPeriods = _periods;
    }

    function setOperator(address _account) external onlyOwner {
        operator[_account] = !operator[_account];
    }

    function setWithdrawSigner(address _withdrawSigner) external onlyOwner {
        withdrawSigner = _withdrawSigner;
    }

    function getStakingTokenIds(
        address _account
    ) external view returns (uint256[] memory) {
        return stakingTokenIds[_account];
    }

    function getStakingPeriods()
        external
        view
        onlyOwner
        returns (uint64[3] memory)
    {
        return stakingPeriods;
    }

    function getWithdrawSigner() external view onlyOwner returns (address) {
        return withdrawSigner;
    }

    function staking(
        uint256[] calldata _tokenIds,
        uint256 _stakeTime
    ) external whenNotPaused nonReentrant returns (bool) {
        uint256 length = _tokenIds.length;

        address _account = _msgSender();

        require(length > 0, "invalid tokenIds");

        require(
            _stakeTime == stakingPeriods[0] ||
                _stakeTime == stakingPeriods[1] ||
                _stakeTime == stakingPeriods[2],
            "invalid stake time"
        );

        if (stakingTokenIds[_account].length == 0) {
            unchecked {
                accountTotal += 1;
            }
        }

        for (uint256 i = 0; i < length; ++i) {
            uint256 _tokenId = _tokenIds[i];

            require(!stakingDatas[_tokenId].stakedState, "invalid stake state");

            require(ygme.ownerOf(_tokenId) == _account, "invalid owner");

            StakingData memory _data = StakingData({
                owner: _account,
                stakedState: true,
                startTime: uint128(block.timestamp),
                endTime: uint128(block.timestamp + _stakeTime)
            });

            stakingDatas[_tokenId] = _data;

            if (stakingTokenIds[_account].length == 0) {
                stakingTokenIds[_account] = [_tokenId];
            } else {
                stakingTokenIds[_account].push(_tokenId);
            }

            ygme.safeTransferFrom(_account, address(this), _tokenId);

            emit Staking(
                _account,
                _tokenId,
                address(ygme),
                _data.startTime,
                _data.endTime,
                1
            );
        }

        unchecked {
            ygmeTotal += uint128(length);
        }

        return true;
    }

    function unStake(
        uint256[] calldata _tokenIds
    ) external whenNotPaused nonReentrant returns (bool) {
        uint256 length = _tokenIds.length;

        address _account = _msgSender();

        require(length > 0, "invalid tokenIds");

        for (uint256 i = 0; i < length; ++i) {
            uint256 _tokenId = _tokenIds[i];

            StakingData memory _data = stakingDatas[_tokenId];

            require(_data.owner == _account, "invalid account");

            require(_data.stakedState, "invalid stake state");

            require(block.timestamp >= _data.endTime, "too early to unStake");

            uint256 _len = stakingTokenIds[_account].length;

            for (uint256 j = 0; j < _len; ++j) {
                if (stakingTokenIds[_account][j] == _tokenId) {
                    stakingTokenIds[_account][j] = stakingTokenIds[_account][
                        _len - 1
                    ];
                    stakingTokenIds[_account].pop();
                    break;
                }
            }

            emit Staking(
                _account,
                _tokenId,
                address(ygme),
                _data.startTime,
                block.timestamp,
                2
            );

            delete stakingDatas[_tokenId];

            ygme.safeTransferFrom(address(this), _account, _tokenId);
        }

        if (stakingTokenIds[_account].length == 0) {
            accountTotal -= 1;
        }

        ygmeTotal -= uint128(length);

        return true;
    }

    function withdrawERC20(
        bytes calldata data,
        bytes calldata signature
    ) external nonReentrant returns (bool) {
        require(data.length > 0, "invalid data");

        bytes32 hash = keccak256(data);

        _verifySignature(hash, signature);

        (uint256 orderId, address account, uint256 amount) = abi.decode(
            data,
            (uint256, address, uint256)
        );

        require(!orderIsInvalid[orderId], "invalid orderId");

        require(account == _msgSender(), "invalid account");

        orderIsInvalid[orderId] = true;

        ygio.safeTransfer(account, amount);

        emit WithdrawERC20(orderId, account, amount);

        return true;
    }

    function _verifySignature(
        bytes32 hash,
        bytes calldata signature
    ) internal view {
        hash = hash.toEthSignedMessageHash();

        address signer = hash.recover(signature);

        require(signer == withdrawSigner, "invalid signature");
    }

    function aggregateStaticCall(
        Call[] calldata calls
    )
        external
        view
        onlyOperator
        returns (uint256 blockNumber, bytes[] memory returnData)
    {
        blockNumber = block.number;

        uint256 length = calls.length;

        returnData = new bytes[](length);

        Call calldata call;

        for (uint256 i = 0; i < length; ++i) {
            bool success;

            call = calls[i];

            (success, returnData[i]) = call.target.staticcall(call.callData);

            require(success, "call failed");
        }
    }
}
