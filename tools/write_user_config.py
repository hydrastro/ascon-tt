#!/usr/bin/env python3
"""Write src/user_config.json from the VERILOG_DEFINES in src/config.json.

Bypasses tt_tool.py --create-user-config which fails because it runs yosys
without -D defines and cannot parse our parameterized project.v.
"""
import json
from pathlib import Path

cfg = json.loads(Path("src/config.json").read_text())
defines = cfg.get("VERILOG_DEFINES", [])
ucfg = {}
for d in defines:
    if "=" in d:
        k, v = d.split("=", 1)
        try:
            ucfg[k] = int(v)
        except ValueError:
            ucfg[k] = v
    else:
        ucfg[d] = 1
Path("src/user_config.json").write_text(json.dumps(ucfg, indent=2))
print("src/user_config.json:", ucfg)
