#!/usr/bin/env python3
from __future__ import annotations

import re
import subprocess
from pathlib import Path

FILES = [
    Path("src/ascon_tt_aead_bridge.v"),
    Path("src/ascon_tt_serial_frontend.v"),
    Path("src/ascon_core/ascon_aead128_enc_ad.v"),
    Path("src/ascon_core/ascon_aead128_dec_ad.v"),
    Path("src/ascon_core/ascon_perm_unrolled.v"),
    Path("src/ascon_core/ascon_round_comb.v"),
]

KEYWORDS = re.compile(
    r"\b("
    r"IV|iv|state|perm|round|domain|pad|tag|auth|key|nonce|ad_|ad\b|msg|cipher|plain|"
    r"start|done|busy|valid|ready|block|bytes|case|localparam|parameter|assign"
    r")\b"
)

def sh(cmd: list[str]) -> str:
    try:
        return subprocess.check_output(cmd, text=True, stderr=subprocess.DEVNULL).strip()
    except Exception:
        return "unknown"

def strip_comments(text: str) -> str:
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    text = re.sub(r"//.*", "", text)
    return text

def module_headers(text: str) -> list[str]:
    clean = strip_comments(text)
    out: list[str] = []
    for m in re.finditer(r"\bmodule\s+\w+\b", clean):
        start = m.start()
        depth = 0
        seen = False
        for i in range(m.end(), len(clean)):
            ch = clean[i]
            if ch == "(":
                depth += 1
                seen = True
            elif ch == ")":
                depth -= 1
            elif ch == ";" and seen and depth == 0:
                header = re.sub(r"\s+", " ", clean[start:i+1].strip())
                header = header.replace(", ", ",\n  ")
                out.append(header)
                break
    return out

def line_matches(path: Path, text: str) -> list[tuple[int, str]]:
    matches: list[tuple[int, str]] = []
    for n, line in enumerate(text.splitlines(), 1):
        if KEYWORDS.search(line):
            matches.append((n, line.rstrip()))
    return matches

def constants(text: str) -> list[str]:
    found = set(re.findall(r"\b(?:\d+)?'[hHbBdD][0-9a-fA-F_xXzZ]+|\b[0-9]+h[0-9a-fA-F_xXzZ]+\b", text))
    return sorted(found)

def params(text: str) -> list[tuple[int, str]]:
    out = []
    for n, line in enumerate(text.splitlines(), 1):
        if re.search(r"\b(localparam|parameter)\b", line):
            out.append((n, line.rstrip()))
    return out

def perm_instances(text: str) -> list[tuple[int, str]]:
    out = []
    lines = text.splitlines()
    for i, line in enumerate(lines):
        if "ascon_perm_unrolled" in line:
            chunk = "\n".join(f"{j+1:5d}: {lines[j]}" for j in range(max(0, i-3), min(len(lines), i+35)))
            out.append((i+1, chunk))
    return out

def surrounding_cases(text: str) -> list[tuple[int, str]]:
    out = []
    lines = text.splitlines()
    for i, line in enumerate(lines):
        if re.search(r"\bcase\s*\(", line) or re.search(r"\bcasez\s*\(", line):
            chunk = "\n".join(f"{j+1:5d}: {lines[j]}" for j in range(max(0, i-2), min(len(lines), i+80)))
            out.append((i+1, chunk))
    return out

def hierarchy_flags() -> list[str]:
    issues: list[str] = []
    bridge = Path("src/ascon_tt_aead_bridge.v")
    if bridge.exists():
        txt = bridge.read_text(errors="replace")
        if "ascon_aead128_enc_ad" in txt:
            issues.append("current bridge instantiates/references ascon_aead128_enc_ad")
        if "ascon_aead128_dec_ad" in txt:
            issues.append("current bridge instantiates/references ascon_aead128_dec_ad")
        if txt.count("ascon_perm_unrolled") == 0:
            issues.append("bridge does not directly share a permutation; permutation is hidden inside enc/dec cores")
    return issues

def main() -> int:
    out = Path("build/tt14b/shared_core_inputs.md")
    out.parent.mkdir(parents=True, exist_ok=True)

    md: list[str] = []
    md.append("# TT-14B shared-core extraction")
    md.append("")
    md.append(f"Git: `{sh(['git','branch','--show-current'])} {sh(['git','rev-parse','--short','HEAD'])}`")
    md.append("")
    md.append("## Area context")
    md.append("")
    md.append("- Current hardening failed at about `107.397%` placement utilization.")
    md.append("- Required movable-area reduction: `6.89%` for bare 100%, `16.39%` for 90%, `25.89%` for 80%.")
    md.append("- TT-14B target: replace dual enc/dec engines with one shared ASCON permutation/datapath.")
    md.append("")
    md.append("## Design-rule flags")
    md.append("")
    flags = hierarchy_flags()
    if flags:
        for f in flags:
            md.append(f"- {f}")
    else:
        md.append("- no obvious dual-core flags found")
    md.append("")

    for path in FILES:
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
        for h in module_headers(text):
            md.append("```verilog")
            md.append(h)
            md.append("```")
            md.append("")
        if not module_headers(text):
            md.append("_No module headers extracted._")
            md.append("")

        ps = params(text)
        md.append("### Parameters/localparams")
        md.append("")
        if ps:
            md.append("```verilog")
            for n, line in ps:
                md.append(f"{n:5d}: {line}")
            md.append("```")
        else:
            md.append("_None found._")
        md.append("")

        consts = constants(text)
        md.append("### Numeric constants")
        md.append("")
        if consts:
            md.append("```text")
            md.extend(consts[:200])
            if len(consts) > 200:
                md.append(f"... {len(consts)-200} more")
            md.append("```")
        else:
            md.append("_None found._")
        md.append("")

        inst = perm_instances(text)
        md.append("### Permutation instances")
        md.append("")
        if inst:
            for _, chunk in inst:
                md.append("```verilog")
                md.append(chunk)
                md.append("```")
        else:
            md.append("_None found._")
        md.append("")

        cases = surrounding_cases(text)
        md.append("### Case/FSM excerpts")
        md.append("")
        if cases:
            for _, chunk in cases[:8]:
                md.append("```verilog")
                md.append(chunk)
                md.append("```")
        else:
            md.append("_None found._")
        md.append("")

        matches = line_matches(path, text)
        md.append("### Keyword lines")
        md.append("")
        md.append("```verilog")
        for n, line in matches[:260]:
            md.append(f"{n:5d}: {line}")
        if len(matches) > 260:
            md.append(f"... {len(matches)-260} more keyword lines")
        md.append("```")
        md.append("")

    md.append("---")
    md.append("")
    md.append("## TT-14B implementation checklist")
    md.append("")
    md.append("- [ ] Create `src/ascon_tt_aead_shared.v` with the same external bridge interface.")
    md.append("- [ ] Instantiate exactly one `ascon_perm_unrolled` in the production AEAD path.")
    md.append("- [ ] Keep old `ascon_tt_aead_bridge.v` as simulation/reference until shared core passes vectors.")
    md.append("- [ ] Add a parameter such as `USE_SHARED_AEAD` only after the shared core compiles.")
    md.append("- [ ] Run vector tests against both old bridge and shared core.")
    md.append("- [ ] Synthesize shared production profile and compare against the 90% area target.")
    md.append("")
    md.append("## Do not patch yet")
    md.append("")
    md.append("Do not delete the old bridge or replace production until the shared core passes the full AEAD vector test.")
    md.append("")

    out.write_text("\n".join(md))
    print(out)
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
