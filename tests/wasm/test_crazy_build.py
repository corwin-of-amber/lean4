"""Check crazy.makefile allocator selection and incremental builds without a SDK."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import tarfile

ROOT = Path(__file__).resolve().parents[2]

with tempfile.TemporaryDirectory(prefix='crazy-build-', dir=os.environ.get('TMPDIR')) as directory:
    root = Path(directory)
    shutil.copy2(ROOT / 'crazy.makefile', root / 'crazy.makefile')
    (root / 'crazy').mkdir()
    for name in ['platform.mk', 'platform.json', 'configure.py']:
        shutil.copy2(ROOT / 'crazy' / name, root / 'crazy' / name)
    for path in ['src/runtime/object.cpp', 'src/shell/lean.cpp', 'crazy/stubs.cpp',
                 'crazy/include/lean/mimalloc.h', 'crazy/include/lean/version.h', 'crazy/include/githash.h', 'build/release/stage1/lib/temp/Init.c',
                 'build/release/stage1/lib/temp/LakeMain.c', 'lib/export-symbols.txt',
                 'build/release/mimalloc/src/mimalloc/include/mimalloc.h',
                 'build/release/mimalloc/src/mimalloc/src/static.c']:
        file = root / path
        file.parent.mkdir(parents=True, exist_ok=True)
        file.touch()
    tools = root / 'tools'
    tools.mkdir()
    fake = tools / 'fake'
    fake.write_text('#!/usr/bin/env python3\nimport json,sys,os\nfrom pathlib import Path\n'
                    'args=sys.argv[1:]\n'
                    'with open("calls.jsonl","a") as f: f.write(json.dumps(args)+"\\n")\n'
                    'out=args[args.index("-o")+1] if "-o" in args else args[1]\n'
                    'if os.environ.get("BACKEND") == "wasm" and out.startswith("bin/"): out += ".wasm"\n'
                    'Path(out).write_text("built")\n')
    fake.chmod(0o755)
    for name in ['clang', 'clang++', 'ar']:
        (tools / name).symlink_to(fake)
    (tools / 'mv').write_text('#!/bin/sh\nexit 99\n')
    (tools / 'mv').chmod(0o755)
    env = dict(os.environ, PATH=str(tools) + os.pathsep + os.environ['PATH'])

    def build(*options):
        log = root / 'calls.jsonl'
        if log.exists():
            log.unlink()
        subprocess.run(['make', '-f', 'crazy.makefile', 'both', *options], cwd=root,
                       env=env, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        return [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []

    baseline = build('MIMALLOC=0', 'DLSYM=none')
    assert baseline and all('-DLEAN_MIMALLOC' not in call for call in baseline)
    assert all('-Oz' in call for call in baseline if '-c' in call)
    enabled = build('MIMALLOC=1', 'OPT=O3', 'DLSYM=none')
    compiles = [call for call in enabled if '-c' in call]
    assert compiles and all('-DLEAN_MIMALLOC' in call and '-O3' in call for call in compiles)
    unity = [call for call in compiles if 'build/release/mimalloc/src/mimalloc/src/static.c' in call]
    assert len(unity) == 1
    assert '-DMI_USE_PTHREADS=1' in unity[0] and '-DMI_TLS_MODEL_LOCAL=1' in unity[0]
    assert not any('MI_MALLOC_OVERRIDE' in flag for call in enabled for flag in call)
    assert not build('MIMALLOC=1', 'OPT=O3', 'DLSYM=none'), 'An unchanged build must be incremental'
    back = build('MIMALLOC=0', 'DLSYM=none')
    assert back and not any('-c' in call for call in back), 'Reuse the libc objects when switching back'
    assert any('lib/liblean-native-stage1-Oz-none.a' in call and '-o' in call for call in back)
    again = build('MIMALLOC=1', 'OPT=O3', 'DLSYM=none')
    assert again and not any('-c' in call for call in again)
    assert any('lib/liblean-native-stage1-O3-none-mimalloc.a' in call and '-o' in call for call in again)
    compact = build('MIMALLOC=1', 'DLSYM=none')
    assert all('-Oz' in call and '-DLEAN_MIMALLOC' in call for call in compact if '-c' in call)
    assert any('lib/liblean-native-stage1-Oz-none-mimalloc.a' in call and '-o' in call for call in compact)
    assert not build('MIMALLOC=1', 'DLSYM=none')
    # STAGE and DLSYM must select distinct objects even at the same OPT/allocator settings.
    for path in ['stage0/src/runtime/object.cpp', 'stage0/src/shell/lean.cpp',
                 'stage0/stdlib/Init.c', 'stage0/stdlib/LakeMain.c',
                 'crazy/dyntable/crc.c', 'crazy/dyntable/crc.ts',
                 'crazy/dyntable/dlsym_dyn.cpp', 'crazy/extract-native-exports.ts']:
        file = root / path
        file.parent.mkdir(parents=True, exist_ok=True)
        file.touch()
    stage0 = build('STAGE=0', 'MIMALLOC=0', 'DLSYM=none')
    assert any('-DLEAN_IS_STAGE0' in call for call in stage0 if '-c' in call)
    assert any('obj-native-stage0-' in flag for call in stage0 for flag in call)
    assert not build('STAGE=0', 'MIMALLOC=0', 'DLSYM=none')
    (root / 'lib/dyn.c').touch()
    dynamic = build('MIMALLOC=0', 'DLSYM=dyn', 'TSX=true')
    assert any('-DAMBER_DL_DYNTABLE' in call for call in dynamic if '-c' in call)
    assert any('obj-native-stage1-Oz-dyn/' in flag for call in dynamic for flag in call)
    wasm = build('MIMALLOC=0', 'DLSYM=none', 'BACKEND=wasm')
    assert any('obj-wasm-stage1-Oz-none/' in flag for call in wasm for flag in call)
    changed_flags = build('MIMALLOC=0', 'DLSYM=none', 'CFLAGS=-O2')
    assert len([call for call in changed_flags if '-c' in call]) >= 4
    assert not build('MIMALLOC=0', 'DLSYM=none', 'CFLAGS=-O2')
    for name in ['src/static.c', 'include/mimalloc.h']:
        target = root / 'alternate-mimalloc' / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(root / 'build/release/mimalloc/src/mimalloc' / name, target)
    relocated = build('MIMALLOC=1', 'DLSYM=none', 'MIMALLOC_DIR=alternate-mimalloc')
    assert any('alternate-mimalloc/src/static.c' in call for call in relocated)
    assert len([call for call in relocated if '-c' in call]) >= 4
    assert not build('MIMALLOC=1', 'DLSYM=none', 'MIMALLOC_DIR=alternate-mimalloc')
    print('crazy build checks passed: backend, stage, flags, allocator source, optimization, symbol lookup and incremental reuse')

    # An installed library tree must not turn `cd` into a two-directory command.
    library = root / 'build-wasmer-fs/home/init/build/lib/lean'
    installed = root / 'build-wasmer-fs/usr/lib/lean'
    installed.mkdir(parents=True)
    (installed / 'stale.olean').touch()
    extensions = ['.olean', '.olean.server', '.olean.private', '.ir', '.ir.sig']
    for name in ['Init', 'Std', 'Lean', 'LeanExport', 'Lake']:
        directory = library / name
        directory.mkdir(parents=True)
        for extension in extensions:
            (directory / ('Probe' + extension)).touch()
    for extension in extensions:
        (library / ('Init' + extension)).touch()
    subprocess.run(['make', '-f', 'crazy.makefile', 'lib-wasm-tars'], cwd=root,
                   env=env, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    for name in ['Std', 'Lean', 'LeanExport', 'Lake']:
        with tarfile.open(root / f'lib/{name}.tar') as archive:
            assert set(archive.getnames()) == {'Probe' + extension for extension in extensions}
    print('library packaging selects one tree and preserves module metadata')
