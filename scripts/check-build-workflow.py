#!/usr/bin/env python3
"""Run after --build-only: a failed compile must preserve the verified app."""
import hashlib
import os
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parent.parent
app = root / 'build/Margin.app'

def fingerprint():
    return {str(p.relative_to(app)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in app.rglob('*') if p.is_file() and not p.is_symlink()}

assert (app / 'Contents/MacOS/Margin').exists(), 'Run --build-only first'
before = fingerprint()
with tempfile.TemporaryDirectory(prefix='margin-build-check-') as folder:
    xcrun = Path(folder) / 'xcrun'
    xcrun.write_text('#!/bin/sh\nif [ "$1" = "--find" ]; then echo /usr/bin/false; else /usr/bin/xcrun "$@"; fi\n')
    xcrun.chmod(0o755)
    env = dict(os.environ, PATH=folder + os.pathsep + os.environ['PATH'])
    result = subprocess.run([str(root / 'scripts/package-dmg.sh'), '--build-only'],
                            env=env, capture_output=True, text=True)
    assert result.returncode != 0, 'The forced compiler failure was ignored'
assert fingerprint() == before, 'A failed build changed the current app'
assert not (root / '.build/build.lock').exists(), 'Failed build leaked its lock'
assert not list((root / '.build').glob('current.*')), 'Failed build left preview artifacts'
print('Build workflow check passed: compiler failure preserved the verified app')
