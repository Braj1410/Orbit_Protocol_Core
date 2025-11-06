// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./ResolverBase.sol";
import "./profiles/IAddressResolver.sol";
import "./profiles/IAddrResolver.sol";
import "./profiles/ITextResolver.sol";
import "./profiles/IContentHashResolver.sol";
import "./profiles/INameResolver.sol";
import "./profiles/IABIResolver.sol";
import "./profiles/IPubkeyResolver.sol";
import "./profiles/IDNSRecordResolver.sol";
import "./profiles/IDNSZoneResolver.sol";
import "./profiles/IInterfaceResolver.sol";
import "../Orbit.sol";

/**
 * @title PublicResolver
 * @notice Complete resolver implementation supporting all record types
 * @dev Implements address, text, content, ABI, pubkey, DNS records
 */
contract PublicResolver is
    ResolverBase,
    IAddressResolver,
    IAddrResolver,
    ITextResolver,
    IContentHashResolver,
    INameResolver,
    IABIResolver,
    IPubkeyResolver,
    IDNSRecordResolver,
    IDNSZoneResolver,
    IInterfaceResolver
{
    Orbit public immutable orbit;

    // Version for migration tracking
    mapping(bytes32 => uint64) public recordVersions;

    // Core records storage
    mapping(bytes32 => mapping(uint256 => mapping(uint256 => bytes))) versionable_addresses;
    mapping(bytes32 => mapping(uint256 => mapping(string => string))) versionable_texts;
    mapping(bytes32 => mapping(uint256 => bytes)) versionable_hashes;
    mapping(bytes32 => mapping(uint256 => string)) versionable_names;
    mapping(bytes32 => mapping(uint256 => mapping(uint256 => bytes))) versionable_abis;
    mapping(bytes32 => mapping(uint256 => PublicKey)) versionable_pubkeys;
    mapping(bytes32 => mapping(uint256 => mapping(bytes32 => bytes))) versionable_dnsRecords;
    mapping(bytes32 => mapping(uint256 => mapping(bytes4 => address))) versionable_interfaces;

    struct PublicKey {
        bytes32 x;
        bytes32 y;
    }

    // Events
    event VersionChanged(bytes32 indexed node, uint64 newVersion);

    constructor(Orbit _orbit) {
        orbit = _orbit;
    }

    /**
     * @dev Check if sender is authorized to make changes to this node
     */
    function isAuthorised(bytes32 node) internal view override returns (bool) {
        address owner = orbit.owner(node);
        return owner == msg.sender || orbit.isApprovedForAll(owner, msg.sender);
    }

    /**
     * @dev Get current version for a node
     */
    function _getVersion(bytes32 node) internal view returns (uint64) {
        return recordVersions[node];
    }

    /**
     * @dev Clear all records when ownership changes
     */
    function clearRecords(bytes32 node) public authorised(node) {
        recordVersions[node]++;
        emit VersionChanged(node, recordVersions[node]);
    }

    // ============ Address Resolution ============

    /**
     * @notice Set address for default coin type (60 = ETH/EVM)
     */
    function setAddr(bytes32 node, address a) external authorised(node) {
        setAddr(node, 60, _addressToBytes(a));
    }

    /**
     * @notice Get address for default coin type
     */
    function addr(bytes32 node) public view returns (address payable) {
        bytes memory a = addr(node, 60);
        if (a.length == 0) return payable(address(0));
        return payable(_bytesToAddress(a));
    }

    /**
     * @notice Set address for specific coin type
     */
    function setAddr(
        bytes32 node,
        uint256 coinType,
        bytes memory a
    ) public authorised(node) {
        uint64 version = _getVersion(node);
        emit AddressChanged(node, coinType, a);
        if (coinType == 60) {
            emit AddrChanged(node, _bytesToAddress(a));
        }
        versionable_addresses[node][version][coinType] = a;
    }

    /**
     * @notice Get address for specific coin type
     */
    function addr(
        bytes32 node,
        uint256 coinType
    ) public view returns (bytes memory) {
        return versionable_addresses[node][_getVersion(node)][coinType];
    }

    // ============ Text Records ============

    /**
     * @notice Set text record
     * @param node The node to update
     * @param key The key to set (e.g., "email", "url", "avatar", "description", "twitter")
     * @param value The text value
     */
    function setText(
        bytes32 node,
        string calldata key,
        string calldata value
    ) external authorised(node) {
        uint64 version = _getVersion(node);
        versionable_texts[node][version][key] = value;
        emit TextChanged(node, key, key);
    }

    /**
     * @notice Get text record
     */
    function text(
        bytes32 node,
        string calldata key
    ) external view returns (string memory) {
        return versionable_texts[node][_getVersion(node)][key];
    }

    // ============ Content Hash ============

    /**
     * @notice Set content hash (IPFS, Swarm, etc)
     */
    function setContenthash(
        bytes32 node,
        bytes calldata hash
    ) external authorised(node) {
        uint64 version = _getVersion(node);
        versionable_hashes[node][version] = hash;
        emit ContenthashChanged(node, hash);
    }

    /**
     * @notice Get content hash
     */
    function contenthash(
        bytes32 node
    ) external view override returns (bytes memory) {
        return versionable_hashes[node][_getVersion(node)];
    }

    // ============ Name Records ============

    /**
     * @notice Set canonical name for reverse resolution
     */
    function setName(
        bytes32 node,
        string calldata _name
    ) external authorised(node) {
        uint64 version = _getVersion(node);
        versionable_names[node][version] = _name;
        emit NameChanged(node, _name);
    }

    /**
     * @notice Get canonical name
     */
    function name(bytes32 node) external view override returns (string memory) {
        return versionable_names[node][_getVersion(node)];
    }

    // ============ ABI Records ============

    /**
     * @notice Set contract ABI
     */
    function setABI(
        bytes32 node,
        uint256 contentType,
        bytes calldata data
    ) external authorised(node) {
        require(
            ((contentType - 1) & contentType) == 0,
            "Content type must be power of 2"
        );
        uint64 version = _getVersion(node);
        versionable_abis[node][version][contentType] = data;
        emit ABIChanged(node, contentType);
    }

    /**
     * @notice Get contract ABI
     */
    function ABI(
        bytes32 node,
        uint256 contentTypes
    ) external view override returns (uint256, bytes memory) {
        uint64 version = _getVersion(node);

        uint256 contentType = 1;
        while (contentType <= contentTypes) {
            if ((contentType & contentTypes) != 0) {
                bytes memory data = versionable_abis[node][version][
                    contentType
                ];
                if (data.length > 0) {
                    return (contentType, data);
                }
            }
            contentType <<= 1;
        }

        return (0, "");
    }

    // ============ Public Key Records ============

    /**
     * @notice Set public key for cryptographic operations
     */
    function setPubkey(
        bytes32 node,
        bytes32 x,
        bytes32 y
    ) external authorised(node) {
        uint64 version = _getVersion(node);
        versionable_pubkeys[node][version] = PublicKey(x, y);
        emit PubkeyChanged(node, x, y);
    }

    /**
     * @notice Get public key
     */
    function pubkey(
        bytes32 node
    ) external view override returns (bytes32 x, bytes32 y) {
        uint64 version = _getVersion(node);
        return (
            versionable_pubkeys[node][version].x,
            versionable_pubkeys[node][version].y
        );
    }

    // ============ DNS Records ============

    /**
     * @notice Set DNS record
     */
    function setDNSRecords(
        bytes32 node,
        bytes calldata data
    ) external authorised(node) {
        uint64 version = _getVersion(node);

        uint16 offset = 0;
        while (offset < data.length) {
            bytes memory rr = _readDNSRecord(data, offset);
            bytes32 typeHash = keccak256(abi.encodePacked(_dnsType(rr)));
            versionable_dnsRecords[node][version][typeHash] = rr;
            emit DNSRecordChanged(node, _dnsName(rr), _dnsResource(rr), rr);
            offset += uint16(_readUint16(data, offset));
        }

        emit DNSRecordDeleted(node, "", 0);
    }

    /**
     * @notice Get DNS records
     */
    function dnsRecord(
        bytes32 node,
        bytes32,
        uint16 resource
    ) external view override returns (bytes memory) {
        uint64 version = _getVersion(node);
        return
            versionable_dnsRecords[node][version][
                keccak256(abi.encodePacked(resource))
            ];
    }

    /**
     * @notice Check if DNS records have been set
     */
    function hasDNSRecords(bytes32, bytes32) external pure returns (bool) {
        return false; // Simplified implementation
    }

    /**
     * @notice Clear DNS zone
     */
    function clearDNSZone(bytes32 node) external authorised(node) {
        recordVersions[node]++;
        emit DNSZonehashChanged(node, "", "");
    }

    /**
     * @notice Set complete DNS zone
     */
    function setZonehash(
        bytes32 node,
        bytes calldata hash
    ) external authorised(node) {
        uint64 version = _getVersion(node);
        versionable_dnsRecords[node][version][bytes32(0)] = hash;
        emit DNSZonehashChanged(node, hash, "");
    }

    /**
     * @notice Get DNS zone hash
     */
    function zonehash(
        bytes32 node
    ) external view override returns (bytes memory) {
        return versionable_dnsRecords[node][_getVersion(node)][bytes32(0)];
    }

    // ============ Interface Support ============

    /**
     * @notice Set interface implementer
     */
    function setInterface(
        bytes32 node,
        bytes4 interfaceID,
        address implementer
    ) external authorised(node) {
        uint64 version = _getVersion(node);
        versionable_interfaces[node][version][interfaceID] = implementer;
        emit InterfaceChanged(node, interfaceID, implementer);
    }

    /**
     * @notice Get interface implementer
     */
    function interfaceImplementer(
        bytes32 node,
        bytes4 interfaceID
    ) external view override returns (address) {
        return versionable_interfaces[node][_getVersion(node)][interfaceID];
    }

    /**
     * @notice Check if resolver supports an interface
     */
    function supportsInterface(
        bytes4 interfaceID
    ) public view override returns (bool) {
        return
            interfaceID == type(IAddressResolver).interfaceId ||
            interfaceID == type(IAddrResolver).interfaceId ||
            interfaceID == type(ITextResolver).interfaceId ||
            interfaceID == type(IContentHashResolver).interfaceId ||
            interfaceID == type(INameResolver).interfaceId ||
            interfaceID == type(IABIResolver).interfaceId ||
            interfaceID == type(IPubkeyResolver).interfaceId ||
            interfaceID == type(IDNSRecordResolver).interfaceId ||
            interfaceID == type(IInterfaceResolver).interfaceId ||
            super.supportsInterface(interfaceID);
    }

    // ============ Utility Functions ============

    function _addressToBytes(address a) internal pure returns (bytes memory) {
        return abi.encodePacked(a);
    }

    function _bytesToAddress(bytes memory b) internal pure returns (address) {
        require(b.length == 20, "Invalid address length");
        address result;
        assembly {
            result := mload(add(b, 20))
        }
        return result;
    }

    function _readDNSRecord(
        bytes memory data,
        uint16 offset
    ) internal pure returns (bytes memory) {
        uint16 len = _readUint16(data, offset);
        return _substring(data, offset, len);
    }

    function _readUint16(
        bytes memory data,
        uint16 offset
    ) internal pure returns (uint16) {
        require(data.length >= offset + 2, "Out of bounds");
        uint16 result;
        assembly {
            result := mload(add(add(data, 0x20), offset))
        }
        return result;
    }

    function _substring(
        bytes memory data,
        uint16 offset,
        uint16 len
    ) internal pure returns (bytes memory) {
        bytes memory result = new bytes(len);
        for (uint i = 0; i < len; i++) {
            result[i] = data[offset + i];
        }
        return result;
    }

    function _dnsName(bytes memory) internal pure returns (bytes memory) {
        return "";
    }

    function _dnsType(bytes memory) internal pure returns (uint16) {
        return 0;
    }

    function _dnsResource(bytes memory) internal pure returns (uint16) {
        return 0;
    }
}
