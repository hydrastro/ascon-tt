#!/usr/bin/env python3
"""Generate src/user_config.json and src/config_merged.json from info.yaml + src/config.json.

This avoids tt_tool.py --create-user-config issues with parameterized/define-heavy RTL,
while preserving the Tiny Tapeout fields LibreLane needs.
"""
from __future__ import annotations
import json, re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / 'src'

def parse_info() -> dict:
    text = (ROOT / 'info.yaml').read_text()
    try:
        import yaml
        return yaml.safe_load(text)
    except Exception:
        top = ''
        tiles = ''
        clock_hz = 0
        sources = []
        in_sources = False
        for line in text.splitlines():
            stripped = line.strip()
            if stripped.startswith('top_module:'):
                top = stripped.split(':', 1)[1].strip().strip('"')
            elif stripped.startswith('tiles:'):
                tiles = stripped.split(':', 1)[1].strip().strip('"')
            elif stripped.startswith('clock_hz:'):
                try:
                    clock_hz = int(stripped.split(':', 1)[1].strip())
                except ValueError:
                    pass
            elif stripped.startswith('source_files:'):
                in_sources = True
            elif in_sources and stripped.startswith('-'):
                sources.append(stripped[1:].strip().strip('"'))
            elif in_sources and stripped and not stripped.startswith('-'):
                in_sources = False
        return {'project': {'top_module': top, 'tiles': tiles, 'clock_hz': clock_hz, 'source_files': sources}}

def main() -> int:
    cfg = json.loads((SRC / 'config.json').read_text())
    info = parse_info()
    project = info.get('project', {})
    top = project.get('top_module') or cfg.get('DESIGN_NAME', 'tt_um_ascon_aead')
    sources = project.get('source_files') or [p.replace('dir::', '') for p in cfg.get('VERILOG_FILES', [])]

    user_cfg = {
        'DESIGN_NAME': top,
        'VERILOG_FILES': [f'dir::{s}' for s in sources],
        'DIE_AREA': cfg['DIE_AREA'],
        'FP_DEF_TEMPLATE': cfg['FP_DEF_TEMPLATE'],
        'VDD_PIN': cfg.get('VDD_PIN', 'VDD'),
        'GND_PIN': cfg.get('GND_PIN', 'VSS'),
        'RT_MAX_LAYER': cfg.get('RT_MAX_LAYER', 'Metal4'),
    }
    for d in cfg.get('VERILOG_DEFINES', []):
        if '=' in d:
            k, v = d.split('=', 1)
            try:
                v = int(v)
            except ValueError:
                pass
            user_cfg[k] = v
        else:
            user_cfg[d] = 1

    merged = dict(cfg)
    merged.update(user_cfg)
    (SRC / 'user_config.json').write_text(json.dumps(user_cfg, indent=2) + '\n')
    (SRC / 'config_merged.json').write_text(json.dumps(merged, indent=2) + '\n')
    print('wrote src/user_config.json')
    print('wrote src/config_merged.json')
    print(f"top={top} sources={len(sources)} template={user_cfg['FP_DEF_TEMPLATE']}")
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
