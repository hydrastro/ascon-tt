# TT-12A audit fix — macro-aware production defaults

`src/project.v` now uses production/default macros:

```verilog
parameter integer ENABLE_PERM_DEBUG = `TT_ASCON_DEF_ENABLE_PERM_DEBUG
```

The macro expands to `0` for normal synthesis and to `1` only when debug
simulations compile with `-DTT_DEBUG_DEFAULTS`.

The TT-9 audit originally required literal `= 0`, so it falsely failed the
pre-GDS chain. The audit now accepts either literal production defaults or the
macro form when the macro's normal branch defines the production value.
