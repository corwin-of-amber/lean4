"""Check crazy.makefile allocator selection and incremental builds without a SDK."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]

with tempfile.TemporaryDirectory(prefix='crazy-build-', dir=os.environ.get('TMPDIR')) as directory:
    root = Path(directory)
    shutil.copy2(ROOT / 'crazy.makefile', root / 'crazy.makefile')
    for path in ['src/runtime/object.cpp', 'src/shell/lean.cpp', 'crazy/stubs.cpp',
                 'crazy/mimalloc.cpp', 'build/release/stage1/lib/temp/Init.c',
                 'build/release/stage1/lib/temp/LakeMain.c', 'lib/export-symbols.txt',
                 'build/release/mimalloc/src/mimalloc/include/mimalloc.h',
                 'build/release/mimalloc/src/mimalloc/src/static.c']:
        file = root / path
        file.parent.mkdir(parents=True, exist_ok=True)
        file.touch()
    tools = root / 'tools'
    tools.mkdir()
    fake = tools / 'fake'
    fake.write_text('#!/usr/bin/env python3\nimport json,sys\nfrom pathlib import Path\n'
                    'args=sys.argv[1:]\n'
                    'with open("calls.jsonl","a") as f: f.write(json.dumps(args)+"\\n")\n'
                    'out=args[args.index("-o")+1] if "-o" in args else args[1]\n'
                    'Path(out).write_text("built")\n')
    fake.chmod(0o755)
    for name in ['clang', 'clang++', 'ar']:
        (tools / name).symlink_to(fake)
    env = dict(os.environ, PATH=str(tools) + os.pathsep + os.environ['PATH'])

    def build(*options):
        log = root / 'calls.jsonl'
        if log.exists():
            log.unlink()
        subprocess.run(['make', '-f', 'crazy.makefile', 'both', *options], cwd=root,
                       env=env, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        return [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []

    baseline = build()
    assert baseline and all('-DLEAN_MIMALLOC' not in call for call in baseline)
    assert all('-Oz' in call for call in baseline if '-c' in call)
    enabled = build('MIMALLOC=1', 'OPT=O3')
    compiles = [call for call in enabled if '-c' in call]
    assert compiles and all('-DLEAN_MIMALLOC' in call and '-O3' in call for call in compiles)
    unity = [call for call in compiles if 'crazy/mimalloc.cpp' in call]
    assert len(unity) == 1
    assert '-DMI_USE_PTHREADS=1' in unity[0] and '-DMI_TLS_MODEL_LOCAL=1' in unity[0]
    assert not any('MI_MALLOC_OVERRIDE' in flag for call in enabled for flag in call)
    assert not build('MIMALLOC=1', 'OPT=O3'), 'An unchanged build must be incremental'
    back = build()
    assert back and not any('-c' in call for call in back), 'Reuse the libc objects when switching back'
    assert any('lib/liblean.a' in call and '-o' in call for call in back)
    again = build('MIMALLOC=1', 'OPT=O3')
    assert again and not any('-c' in call for call in again)
    assert any('lib/liblean-O3-mimalloc.a' in call and '-o' in call for call in again)
    compact = build('MIMALLOC=1')
    assert all('-Oz' in call and '-DLEAN_MIMALLOC' in call for call in compact if '-c' in call)
    assert any('lib/liblean-mimalloc.a' in call and '-o' in call for call in compact)
    assert not build('MIMALLOC=1')
    print('crazy build checks passed: defaults, mimalloc, optimization, incremental builds and mode switching')
