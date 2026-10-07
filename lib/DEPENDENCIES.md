# Vendored dependencies

All imported Solidity files are ordinary repository files. No package install, git submodule,
or network access is required for a build once Foundry and solc 0.8.26 are installed.

- OpenZeppelin Contracts **v5.0.2**: the unmodified ERC-20 dependency closure (five Solidity
  files) and MIT license. Source: https://github.com/OpenZeppelin/openzeppelin-contracts/tree/v5.0.2
  Files were downloaded from that tag on raw.githubusercontent.com.
- forge-std **v1.9.7**: unmodified `src/`, `LICENSE-APACHE`, and `LICENSE-MIT`, used only by tests.
  Source: https://github.com/foundry-rs/forge-std/tree/v1.9.7
  Archive: https://codeload.github.com/foundry-rs/forge-std/tar.gz/refs/tags/v1.9.7
  Archive SHA-256: `45157353ab49eab01d294565866731e599b32401757229689ee459aa26b7ee94`.

`SHA256SUMS` records every vendored source/license file. Check from the repository root with
`sha256sum --check lib/SHA256SUMS`. Root `remappings.txt` resolves all imports locally.
