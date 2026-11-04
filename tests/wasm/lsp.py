"""Check WASIX LSP worker startup, diagnostics, and graceful shutdown."""
import argparse
import json
from pathlib import Path
from queue import Queue
import subprocess
import tempfile
from threading import Thread

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--wasmer', default='wasmer')
parser.add_argument('--lean', default='bin/lean.wasm')
parser.add_argument('--filesystem', type=Path, default=Path('build-wasmer-fs'))
args = parser.parse_args()
with tempfile.TemporaryDirectory(prefix='lean-wasix-lsp-') as directory:
    root = Path(directory)
    (root/'Check.lean').write_text('theorem checkLsp : True := True.intro\n')
    command = [args.wasmer, 'run', '--stack-size=16000000',
        '--volume', f'{args.filesystem.resolve()}/usr:/usr',
        '--volume', f'{args.filesystem.resolve()}/etc:/etc',
        '--volume', f'{root}:/home', '--cwd', '/home', '--env', 'LEAN_NUM_THREADS=1',
        args.lean, '--', '-j1', '-s4000', '-Dinterpreter.prefer_native=false', '--server']
    process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    messages = Queue()
    errors = bytearray()
    def read_messages():
        try:
            while line := process.stdout.readline():
                headers = {}
                while line.strip():
                    key, value = line.decode().split(':', 1)
                    headers[key.lower()] = value.strip()
                    line = process.stdout.readline()
                messages.put(json.loads(process.stdout.read(int(headers['content-length']))))
        except Exception as error:
            messages.put(error)
        finally:
            messages.put(None)
    def read_errors():
        while chunk := process.stderr.read(4096): errors.extend(chunk)
    readers = [Thread(target=read_messages, daemon=True), Thread(target=read_errors, daemon=True)]
    for reader in readers: reader.start()
    def send(method, params, id=None):
        value = {'jsonrpc': '2.0', 'method': method, 'params': params}
        if id is not None: value['id'] = id
        write(value)
    def write(value):
        body = json.dumps(value).encode()
        process.stdin.write(f'Content-Length: {len(body)}\r\n\r\n'.encode() + body)
        process.stdin.flush()
    def receive(id):
        while True:
            value = messages.get(timeout=180)
            assert isinstance(value, dict), (value, errors.decode(errors='replace'))
            if 'method' in value and 'id' in value:
                write({'jsonrpc': '2.0', 'id': value['id'], 'result': None})
            elif value.get('id') == id:
                assert 'error' not in value, value
                return value
            elif value.get('method') == 'textDocument/publishDiagnostics':
                assert not value['params']['diagnostics'], value
    try:
        send('initialize', {'processId': None, 'rootUri': 'file:///home', 'capabilities': {}}, 1)
        receive(1)
        send('initialized', {})
        send('textDocument/didOpen', {'textDocument': {'uri': 'file:///home/Check.lean',
            'languageId': 'lean4', 'version': 1, 'text': (root/'Check.lean').read_text()}})
        send('textDocument/waitForDiagnostics', {'uri': 'file:///home/Check.lean', 'version': 1}, 2)
        receive(2)
        send('shutdown', None, 3)
        receive(3)
        send('exit', None)
        process.stdin.close()
        assert process.wait(timeout=60) == 0, errors.decode(errors='replace')
    finally:
        if process.poll() is None:
            process.kill()
            process.wait()
        for reader in readers: reader.join(timeout=2)
        for stream in [process.stdin, process.stdout, process.stderr]: stream.close()
print('WASIX LSP worker, diagnostics, and shutdown checks passed')
