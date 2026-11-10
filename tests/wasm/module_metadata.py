"""Reject missing/corrupt module metadata and test the CLI UInt32 boundary."""
import argparse
import os
from pathlib import Path
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--lean', required=True)
args = parser.parse_args()
with tempfile.TemporaryDirectory(prefix='lean-metadata-') as directory:
    root = Path(directory)
    def run(file, *options):
        return subprocess.run([args.lean, *options, str(root/file)], cwd=root,
            env=dict(os.environ, LEAN_PATH=str(root)), text=True, capture_output=True)
    (root/'Probe.lean').write_text('module\nimport Init\n/-! Module metadata regression fixture. -/\npublic def probe : Nat := 7\n')
    result = run('Probe.lean', '-o', str(root/'Probe.olean'))
    assert result.returncode == 0, result.stdout + result.stderr
    (root/'Import.lean').write_text('import Probe\n#check probe\n')
    assert run('Import.lean').returncode == 0
    for suffix in ['server', 'private']:
        file = root/f'Probe.olean.{suffix}'
        contents = file.read_bytes()
        try:
            file.write_bytes(b'corrupt metadata')
            result = run('Import.lean')
            assert result.returncode != 0 and 'invalid header' in result.stdout, result.stdout
            file.unlink()
            assert run('Import.lean').returncode != 0
        finally: file.write_bytes(contents)
    assert run('Import.lean').returncode == 0
    for code in [0, 7, 255, 4294967295]:
        (root/'Exit.lean').write_text(f'def main : IO UInt32 := pure {code}\n')
        result = run('Exit.lean', '--run')
        assert result.returncode == code % 256, (code, result.returncode, result.stdout)
print('Strict metadata, recovery, and UInt32 CLI checks passed')
