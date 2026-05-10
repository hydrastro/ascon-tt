# TT-12 repo hygiene repair

This repair does three things:

1. restores `.gitignore` so build/layout artifacts do not get committed;
2. removes local `build/` products from the working tree;
3. converts `tt/` from a regular clone into a real Git submodule when possible.

Expected clean dependency model:

- `src/ascon_core/` contains the vendored ASCON RTL required by hardening;
- `tt/` is a submodule pointing to `TinyTapeout/tt-support-tools`;
- generated GDS/DEF/LEF/log/report artifacts are ignored from Git and can be
  captured later with the TT-12A artifact tools.

After running the repair:

```sh
make clean && make sanity
make tt10-flow-preflight
make tt11b-tools-check
make tt12a-artifact-policy-check
```
