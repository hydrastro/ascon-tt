# TT-11B — Tiny Tapeout support tools submodule

This phase records `tt-support-tools` as a Git submodule at `tt/`.

Why use a submodule:

- the exact support-tools revision is pinned in Git;
- the repo remains lightweight because tool code is not copied into normal files;
- collaborators can reproduce the same hardening helper scripts with
  `git submodule update --init --recursive`.

Clone with submodules:

```sh
git clone --recurse-submodules <repo-url>
```

Initialize after an ordinary clone:

```sh
git submodule update --init --recursive
```

Useful targets:

```sh
make tt11b-tools-check
make tt12-create-user-config
make tt12-harden
make tt12-print-warnings
make tt12-print-stats
make tt12-print-cell-category
```

The first complete hardening attempt can be launched with:

```sh
make tt12-first-hardening-run
```

This assumes the local hardening environment is already installed and configured
with the required PDK/LibreLane variables.
