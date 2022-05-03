// Altura ERC721 token
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721URIStorageUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract AlturaERC721 is
  OwnableUpgradeable,
  ERC721BurnableUpgradeable,
  ERC721EnumerableUpgradeable,
  ERC721URIStorageUpgradeable
{
  function initialize(
    string memory _name,
    string memory _symbol,
    address _creator
  ) public initializer {
    __ERC721_init(_name, _symbol);
    __Ownable_init();
    __ERC721Burnable_init();
    __ERC721Enumerable_init();
    __ERC721URIStorage_init();
    __AlturaERC721_init_unchained(_creator);
  }

  function __AlturaERC721_init_unchained(address _creator)
    internal
    initializer
  {
    require(_creator != address(0), "!zero address");

    transferOwnership(_creator);
  }

  function supportsInterface(bytes4 _interfaceId)
    public
    view
    virtual
    override(ERC721Upgradeable, ERC721EnumerableUpgradeable)
    returns (bool)
  {}

  /**
   * @dev Return token uri.
   *
   * Requirements:
   *
   * - `_tokenId` must exist.
   */
  function tokenURI(uint256 _tokenId)
    public
    view
    override(ERC721Upgradeable, ERC721URIStorageUpgradeable)
    returns (string memory)
  {
    return ERC721URIStorageUpgradeable.tokenURI(_tokenId);
  }

  /**
   * @dev Mint a new token.
   *
   * Requirements:
   *
   */
  function mint(uint256 _tokenId, string memory _tokenURI)
    public
    virtual
    onlyOwner
  {
    super._mint(_msgSender(), _tokenId);
    super._setTokenURI(_tokenId, _tokenURI);
  }

  /**
   * @dev Set token uri.
   *
   * Requirements:
   *
   * - `_tokenId` must exist.
   */
  function setTokenURI(uint256 _tokenId, string memory _tokenURI)
    external
    onlyOwner
  {
    super._setTokenURI(_tokenId, _tokenURI);
  }

  function _beforeTokenTransfer(
    address _from,
    address _to,
    uint256 _tokenId
  ) internal virtual override(ERC721Upgradeable, ERC721EnumerableUpgradeable) {}

  function _burn(uint256 _tokenId)
    internal
    virtual
    override(ERC721Upgradeable, ERC721URIStorageUpgradeable)
  {}

  uint256[50] private __gap;
}
