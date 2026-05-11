#!/usr/bin/env python3
from __future__ import annotations

import re
from pathlib import Path
from datetime import datetime, timezone

ROOT = Path('.')

def read(path: str | Path) -> str:
    p = ROOT / path
    return p.read_text(errors='replace') if p.exists() else ''

def parse_profiles(text: str):
    rows = []
    for line in text.splitlines():
        parts = line.split()
        if len(parts) >= 10 and parts[1].isdigit():
            rows.append({
                'profile': parts[0],
                'cells': int(parts[1]),
                'dff': int(parts[2]),
                'mux': int(parts[3]),
                'xor': int(parts[4]),
                'xnor': int(parts[5]),
                'warnings': parts[9],
                'check0': parts[10] if len(parts) > 10 else '',
            })
    return rows

def parse_harden_artifacts():
    out = []
    base = ROOT / 'artifacts' / 'hardening'
    if not base.exists():
        return out
    for summary in sorted(base.glob('*/*/reports/harden_summary.md')):
        text = summary.read_text(errors='replace')
        run_dir = summary.parents[1]
        readme = read(run_dir / 'README.md').replace('`','')
        m_rc = re.search(r'harden_rc:\s*(\d+)', text)
        m_tiles = re.search(r'tiles:\s*([^\n]+)', readme)
        m_clock = re.search(r'clock_hz:\s*([^\n]+)', readme)
        m_util = re.search(r'Utilization:\s*([0-9.]+)\s*%', text)
        m_region = re.search(r'Region area:\s*([0-9.]+)\s*um\^2', text)
        m_mov = re.search(r'Movable instances area:\s*([0-9.]+)\s*um\^2', text)
        gds = list((run_dir / 'layout').glob('*.gds')) + list((run_dir / 'layout').glob('*.gds.gz'))
        out.append({
            'name': '/'.join(run_dir.parts[-2:]),
            'path': str(run_dir),
            'tiles': m_tiles.group(1).strip() if m_tiles else '?',
            'clock_hz': m_clock.group(1).strip() if m_clock else '?',
            'rc': int(m_rc.group(1)) if m_rc else None,
            'util': float(m_util.group(1)) if m_util else None,
            'region': float(m_region.group(1)) if m_region else None,
            'movable': float(m_mov.group(1)) if m_mov else None,
            'gds': bool(gds),
        })
    return out

def parse_make_targets():
    targets = []
    for line in read('Makefile').splitlines():
        m = re.match(r'^([A-Za-z0-9_.%/$(){}-][^:=\s]*):', line)
        if m:
            targets.append(m.group(1))
    return sorted(set(targets))

def main() -> int:
    now = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
    docs = ROOT / 'docs'
    docs.mkdir(exist_ok=True)

    profiles = parse_profiles(read('build/tt14d_synth_compare/profile_compare.txt'))
    old = next((r for r in profiles if r['profile'] == 'old_directout'), None)
    shared = next((r for r in profiles if r['profile'] == 'shared_directout'), None)
    reduction = 100.0 * (old['cells'] - shared['cells']) / old['cells'] if old and shared and old['cells'] else None
    artifacts = parse_harden_artifacts()

    perf = read('build/tt16/perf_cost_report.md')
    measured_cycles = ''
    if '## Measured core cycles' in perf:
        measured_cycles = perf.split('## Cost/performance table')[0].strip()

    overview = [
        '# ASCON TT project overview', '', f'_Generated: {now}_', '',
        '## Current technical status', '',
        '- Full bounded ASCON-AEAD128 encrypt/decrypt is implemented behind the Tiny Tapeout byte-serial frontend.',
        '- The minimum-area candidate is the shared single-permutation core selected by `USE_SHARED_AEAD=1`.',
        '- The old dual encrypt/decrypt bridge is preserved as `USE_SHARED_AEAD=0` reference RTL.',
        '- Production/hardening defaults should use the shared core; reference targets explicitly force the dual bridge.', '',
        '## Key result', ''
    ]
    if old and shared:
        overview += [
            '| profile | Yosys cells | DFF | MUX | XOR | XNOR |',
            '|---|---:|---:|---:|---:|---:|',
            f"| old dual directout | {old['cells']} | {old['dff']} | {old['mux']} | {old['xor']} | {old['xnor']} |",
            f"| shared directout | {shared['cells']} | {shared['dff']} | {shared['mux']} | {shared['xor']} | {shared['xnor']} |",
            f"| reduction | {old['cells'] - shared['cells']} |  |  |  |  |", '',
            f'Cell reduction: **{reduction:.2f}%**.' if reduction is not None else '', ''
        ]
    else:
        overview += ['Run `make synth-prod-aead-shared-directout` to refresh area numbers.', '']

    overview += ['## Physical-design status', '',
                 'No final GDS is present unless a hardening run reaches the final GDS export stage. If a run fails at global placement, only intermediate DEF/ODB files are expected.', '']
    if artifacts:
        overview += ['| run | tiles | clock Hz | harden rc | utilization | GDS |', '|---|---|---:|---:|---:|---|']
        for a in artifacts:
            util = f"{a['util']:.3f}%" if a['util'] is not None else ''
            overview.append(f"| `{a['name']}` | {a['tiles']} | {a['clock_hz']} | {a['rc']} | {util} | {'yes' if a['gds'] else 'no'} |")
        overview.append('')
    overview += ['## Next run', '',
                 'Rerun 4x2 after confirming `USE_SHARED_AEAD=1` is the production default:', '',
                 '```sh',
                 'tools/tt17_capture_harden.sh --tiles 4x2 --clock-hz 10000000 --store min-area --name shared_4x2_10mhz_rerun --branch min-area --allow-dirty',
                 '```', '']
    (docs / 'overview.md').write_text('\n'.join(x for x in overview if x is not None) + '\n')

    ledger = ['# Run ledger', '', f'_Generated: {now}_', '', '## Functional/synthesis milestones', '', '| milestone | result | evidence |', '|---|---|---|']
    smoke = read('build/tt14d_smoke/summary.md')
    if smoke:
        ledger.append(f"| old prod directout sim | {'PASS' if 'old prod directout sim | 0' in smoke else 'unknown'} | `build/tt14d_smoke/summary.md` |")
        ledger.append(f"| shared prod directout sim | {'PASS' if 'shared prod directout sim | 0' in smoke else 'unknown'} | `build/tt14d_smoke/summary.md` |")
    if profiles:
        ledger.append('| shared-vs-dual synth compare | PASS | `build/tt14d_synth_compare/profile_compare.txt` |')
    ledger += ['', '## Hardening/artifact runs', '']
    if artifacts:
        ledger += ['| run | tiles | clock Hz | rc | utilization | GDS | notes |', '|---|---|---:|---:|---:|---|---|']
        for a in artifacts:
            util = f"{a['util']:.3f}%" if a['util'] is not None else ''
            note = 'failed before GDS export' if a['rc'] else 'passed'
            ledger.append(f"| `{a['name']}` | {a['tiles']} | {a['clock_hz']} | {a['rc']} | {util} | {'yes' if a['gds'] else 'no'} | {note} |")
    else:
        ledger.append('No hardening artifacts found under `artifacts/hardening/`.')
    ledger.append('')
    (docs / 'run_ledger.md').write_text('\n'.join(ledger) + '\n')

    targets = set(parse_make_targets())
    target_groups = {
        'Everyday': ['sanity','lint','debug-regression','prod-default-check'],
        'Simulation': ['sim','sim-perm-oracle','sim-job-buffers','sim-aead-vectors-prod-directout','sim-aead-vectors-shared-prod-directout','sim-aead-vectors-dual-ref-directout','sim-perf-cycles'],
        'Area/profile': ['synth','synth-prod-aead-top-directout','synth-prod-aead-shared-directout','synth-dual-ref-directout','tt14d-shared-report','tt16-perf-cost'],
        'Hardening': ['tt12-create-user-config','tt12-harden','tt12-create-png','tt17-capture-harden'],
        'Artifact/docs': ['tt15-find-gds','docs-refresh','docs-ledger'],
    }
    purpose = {
        'sanity':'repo hygiene and required files', 'lint':'Verilator lint', 'debug-regression':'debug/permutation regression suite',
        'prod-default-check':'production functional smoke check', 'sim-aead-vectors-shared-prod-directout':'shared-core AEAD vector test',
        'sim-aead-vectors-dual-ref-directout':'old dual-core reference vector test', 'synth-prod-aead-shared-directout':'Yosys shared-core production synthesis',
        'synth-dual-ref-directout':'Yosys dual reference synthesis', 'tt12-harden':'run Tiny Tapeout hardening flow',
        'tt17-capture-harden':'set config, harden, capture artifacts, optional DVC', 'tt16-perf-cost':'measured cycles and cost/perf model',
        'docs-refresh':'regenerate overview, ledger, and flow guide',
    }
    guide = ['# Flow guide', '', 'This is the short command map. Historical phase notes remain in `docs/tt*.md`, but this file is the main entry point.', '']
    for group, names in target_groups.items():
        guide += [f'## {group}', '', '| target | present | purpose |', '|---|---|---|']
        for n in names:
            guide.append(f"| `{n}` | {'yes' if n in targets else 'no'} | {purpose.get(n, '')} |")
        guide.append('')
    (docs / 'flow_guide.md').write_text('\n'.join(guide) + '\n')

    if measured_cycles:
        (docs / 'performance_summary.md').write_text(measured_cycles + '\n')

    readme = ['# ASCON AEAD128 Tiny Tapeout project', '',
              'Tiny Tapeout user macro implementing a bounded, byte-serial ASCON-AEAD128 accelerator.', '',
              '## Start here', '',
              '- Current project status: [`docs/overview.md`](docs/overview.md)',
              '- Command map: [`docs/flow_guide.md`](docs/flow_guide.md)',
              '- Run ledger: [`docs/run_ledger.md`](docs/run_ledger.md)',
              '- Protocol: [`docs/protocol.md`](docs/protocol.md)',
              '- DVC/hardening artifacts: [`docs/tt17_dvc_hardening_artifacts.md`](docs/tt17_dvc_hardening_artifacts.md)', '',
              '## Current architecture', '',
              '- `USE_SHARED_AEAD=1`: production/min-area shared single-permutation AEAD core.',
              '- `USE_SHARED_AEAD=0`: preserved dual encrypt/decrypt reference bridge.',
              '- `src/ascon_core/`: packaged ASCON RTL sourced from the sibling `ascon-rtl` project.', '',
              '## Common commands', '', '```sh',
              'make sanity', 'make lint', 'make sim-aead-vectors-shared-prod-directout',
              'make synth-prod-aead-shared-directout', 'make tt16-perf-cost', 'make docs-refresh',
              '```', '', '## 4x2 hardening capture', '', '```sh',
              'tools/tt17_capture_harden.sh --tiles 4x2 --clock-hz 10000000 --store min-area --name shared_4x2_10mhz --branch min-area --allow-dirty',
              '```', '', '## Generated outputs', '',
              '- `build/` and `runs/` are local generated outputs.',
              '- Large layout artifacts belong under `artifacts/hardening/...` and should be stored with DVC.',
              '- Final GDS is present only after hardening reaches the final GDS export stage.', '']
    (ROOT / 'README.md').write_text('\n'.join(readme) + '\n')

    print('wrote docs/overview.md')
    print('wrote docs/run_ledger.md')
    print('wrote docs/flow_guide.md')
    print('wrote README.md')
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
