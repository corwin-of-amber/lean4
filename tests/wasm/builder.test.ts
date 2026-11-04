import assert from 'node:assert/strict';
import test from 'node:test';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { shrinkwrapManifest } from '../../crazy/manifest.ts';
import { packBuiltArtifacts } from '../../crazy/builder.ts';

test('manifest conversion is pure and handles subdirectories and existing paths', () => {
    const manifest = {version: '1.3.0', packages: [
        {type: 'git', name: 'GameServer', subDir: 'server', rev: 'fixed', configFile: 'lakefile.lean'},
        {type: 'path', name: 'Local', dir: '../local', configFile: 'lakefile.lean'}
    ]};
    const before = JSON.stringify(manifest);
    const result = shrinkwrapManifest(manifest, '../../.lake/packages', true);
    assert.equal(JSON.stringify(manifest), before);
    assert.equal(result.packages[0].dir, '../../.lake/packages/GameServer/server');
    assert.equal(result.packages[0].configFile, 'lakefile.toml');
    assert.equal(result.packages[1].dir, '../local');
    assert.equal(result.packages[1].configFile, 'lakefile.toml');
    assert.equal(result.packages[0].rev, undefined);
});

test('packaging includes metadata and cleans unique staging directories on success and failure', async () => {
    const root = await fs.mkdtemp(path.join(os.tmpdir(), 'lean-package-test-'));
    try {
        const artifacts = path.join(root, 'project/.lake/build/lib/lean');
        await fs.mkdir(artifacts, {recursive: true});
        for (const name of ['A.olean', 'A.olean.server', 'A.olean.private', 'A.ir', 'A.ir.sig'])
            await fs.writeFile(path.join(artifacts, name), 'fixture');
        await Promise.all([packBuiltArtifacts(path.join(root, 'project'), path.join(root, 'a.tar')),
            packBuiltArtifacts(path.join(root, 'project'), path.join(root, 'b.tar'))]);
        const entries = execFileSync('tar', ['tf', path.join(root, 'a.tar')], {encoding: 'utf8'});
        assert.match(entries, /A.olean.server/); assert.match(entries, /A.olean.private/);
        await fs.mkdir(path.join(root, 'empty'));
        await assert.rejects(packBuiltArtifacts(path.join(root, 'empty'), path.join(root, 'a.tar')), /No Lean artifacts/);
        assert.equal((await fs.readdir(root)).filter(name => name.startsWith('.bob-')).length, 0);
        assert.equal(execFileSync('tar', ['tf', path.join(root, 'a.tar')], {encoding: 'utf8'}), entries);
    } finally { await fs.rm(root, {recursive: true, force: true}); }
});
