#!/usr/bin/env python3
from __future__ import annotations

import re
import subprocess
from pathlib import Path

FOCUS = [
    Path("src/ascon_tt_aead_bridge.v"),
    Path("src/ascon_tt_serial_frontend.v"),
    Path("src/ascon_core/ascon_perm_unrolled.v"),
    Path("src/ascon_core/ascon_round_comb.v"),
    Path("src/ascon_core/ascon_aead128_enc_ad.v"),
    Path("src/ascon_core/ascon_aead128_dec_ad.v"),
]

def sh(cmd: list[str]) -> str:
    try:
        return subprocess.check_output(cmd, text=True, stderr=subprocess.DEVNULL).strip()
    except Exception:
        return "unknown"

def module_headers(text: str) -> list[str]:
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    text = re.sub(r"//.*", "", text)
    out: list[str] = []
    for m in re.finditer(r"\bmodule\s+\w+\b", text):
        start = m.start()
        depth = 0
        seen = False
        for i in range(m.end(), len(text)):
            ch = text[i]
            if ch == "(":
                depth += 1
                seen = True
            elif ch == ")":
                depth -= 1
            elif ch == ";" and seen and depth == 0:
                h = re.sub(r"\s+", " ", text[start:i+1].strip())
                h = h.replace(", ", ",\n  ")
                out.append(h)
                break
    return out

def count_token(path: Path, token: str) -> int:
    if not path.exists():
        return 0
    return len(re.findall(rf"\b{re.escape(token)}\b", path.read_text(errors="replace")))

def grep_lines(path: Path, pattern: str) -> list[str]:
    if not path.exists():
        return []
    rx = re.compile(pattern)
    out = []
    for n, line in enumerate(path.read_text(errors="replace").splitlines(), 1):
        if rx.search(line):
            out.append(f"{n:5d}: {line.rstrip()}")
    return out

def main() -> int:
    out = Path("build/tt14c/source_map.md")
    out.parent.mkdir(parents=True, exist_ok=True)

    md: list[str] = []
    md.append("# TT-14C min-area source map")
    md.append("")
    md.append(f"Git: `{sh(['git','branch','--show-current'])} {sh(['git','rev-parse','--short','HEAD'])}`")
    md.append("")
    md.append("## Intended boundary")
    md.append("")
    md.append("- Reuse `ascon_perm_unrolled` and `ascon_round_comb`; do not rewrite them in TT.")
    md.append("- Keep current dual bridge as reference until shared core passes vectors.")
    md.append("- Add the min-area core beside existing files, not over them.")
    md.append("")

    bridge = Path("src/ascon_tt_aead_bridge.v")
    md.append("## Current bridge duplication indicators")
    md.append("")
    md.append("| token | count in bridge |")
    md.append("|---|---:|")
    for tok in ["ascon_aead128_enc_ad", "ascon_aead128_dec_ad", "ascon_perm_unrolled"]:
        md.append(f"| `{tok}` | {count_token(bridge, tok)} |")
    md.append("")

    for path in FOCUS:
        md.append("---")
        md.append("")
        md.append(f"## `{path}`")
        md.append("")
        if not path.exists():
            md.append("MISSING")
            md.append("")
            continue
        text = path.read_text(errors="replace")
        md.append("### Module headers")
        md.append("")
        headers = module_headers(text)
        if headers:
            for h in headers:
                md.append("```verilog")
                md.append(h)
                md.append("```")
                md.append("")
        else:
            md.append("_No module headers found._")
            md.append("")

        md.append("### Important lines")
        md.append("")
        lines = []
        lines += grep_lines(path, r"\bascon_(aead128|perm|round)")
        lines += grep_lines(path, r"\b(localparam|parameter)\b")
        lines += grep_lines(path, r"\b(start|done|busy|valid|ready|auth|tag|key|nonce|state|round|decrypt|encrypt)\b")
        seen = set()
        uniq = []
        for line in lines:
            if line not in seen:
                seen.add(line)
                uniq.append(line)
        md.append("```verilog")
        for line in uniq[:260]:
            md.append(line)
        if len(uniq) > 260:
            md.append(f"... {len(uniq) - 260} more")
        md.append("```")
        md.append("")

    md.append("---")
    md.append("")
    md.append("## Next code action")
    md.append("")
    md.append("Create `src/ascon_tt_aead_shared.v` with the same external bridge interface,")
    md.append("but one internal `ascon_perm_unrolled` instance. Do not switch production")
    md.append("default until vector parity passes.")
    md.append("")

    out.write_text("\n".join(md))
    print(out)
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
