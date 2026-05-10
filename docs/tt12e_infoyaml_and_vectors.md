# TT-12E — Tiny Tapeout info.yaml schema and local vector generation

This repair fixes the first hardening blocker:

```text
Missing 'yaml_version'
Invalid value for 'tiles' in 'project' section: TBD
Missing key 'source_files' in 'project' section
Missing 'pinout' section
```

The Tiny Tapeout support tools expect:

- `project.source_files`, not top-level `source_files`;
- source files listed relative to `./src`;
- a valid tile value such as `8x2`;
- a top-level `pinout` section;
- `yaml_version: 6`.

It also fixes the local simulation vector rule so tests copy generated vectors
into `./sim/generated` from a writable `ASCON_RTL_WORKTREE`, instead of trying
to write into the read-only Nix store flake input.

Default:

```sh
ASCON_RTL_WORKTREE=../ascon-rtl
```

If needed:

```sh
make sim-aead-vectors-prod-directout ASCON_RTL_WORKTREE=/path/to/ascon-rtl
```
