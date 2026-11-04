import fs from 'fs-extra';
import path from 'path';
import { shrinkwrapManifest } from './manifest.ts';
import { spawn, SpawnOptions } from 'child_process';
import { Command } from 'commander';
import { pathToFileURL } from 'node:url';
const platform = fs.readJsonSync(new URL('./platform.json', import.meta.url));


async function copyDirSkippingLake(src: string, dest: string) {
    fs.mkdirSync(dest, {recursive: true});
    await fs.copy(src, dest, {
        filter: src => !['/.lake/build', '/.lake/config']
                        .some(sfx => src.endsWith(sfx))
    });
}

async function translateConfigs(dir: string) {
    let lakefiles =
        (await fs.readdir(dir, {recursive: true, encoding: 'utf-8'}))
        .filter(fn => path.basename(fn) == 'lakefile.lean');

    const lake = path.resolve("build/release/stage1/bin/lake");

    for (let fn of lakefiles) {
        let subdir = path.dirname(path.resolve(dir, fn));
        console.log(subdir);
        await runCommand(lake, ["translate-config", "toml"], {cwd: subdir});
    }
}

async function shrinkwrap(dir: string, toml = false) {
    let manifests =
        (await fs.readdir(dir, {recursive: true, encoding: 'utf-8'}))
        .filter(fn => path.basename(fn) == 'lake-manifest.json');

    let rootPkgDir = '.lake/packages';

    for (let fn of manifests) {
        let fp = path.join(dir, fn),
            manifest = JSON.parse(fs.readFileSync(fp, {encoding: 'utf-8'})),
            pkgDir = path.relative(path.dirname(fn), rootPkgDir);

        if (manifest.packages) {
            manifest = shrinkwrapManifest(manifest, pkgDir, toml);
            for (const pkg of manifest.packages) {
                if (pkg.dir && !isDir(path.resolve(path.dirname(fp), pkg.dir)))
                    throw new Error(`Missing dependency directory: ${pkg.dir} in ${fp}`);
            }
            fs.writeFileSync(fp, JSON.stringify(manifest, null, 1));
        }
    }
}

export async function packBuiltArtifacts(dir: string, output = 'bob.tar') {
    let buildDirs =
        (await fs.readdir(dir, {recursive: true, encoding: 'utf-8'}))
        .filter(fn => fn.endsWith('/build/lib/lean'));

    const outputPath = path.resolve(output);
    await fs.ensureDir(path.dirname(outputPath));
    const stagingDir = await fs.mkdtemp(path.join(path.dirname(outputPath), '.bob-'));
    const extensions = ['.olean', '.olean.server', '.olean.private', '.ir', '.ir.sig'];
    try {
        for (const directory of buildDirs) {
            await fs.copy(path.join(dir, directory), stagingDir, {
                filter: source => isDir(source) || extensions.some(extension => source.endsWith(extension))
            });
        }
        const files = await fs.readdir(stagingDir);
        if (files.length === 0) throw new Error('No Lean artifacts to package');
        await runCommand('tar', ['cf', path.join(stagingDir, 'archive.tar'), '-C', stagingDir, ...files]);
        await fs.rename(path.join(stagingDir, 'archive.tar'), outputPath);
        return outputPath;
    } finally {
        await fs.remove(stagingDir);
    }

}

function isDir(d: string) {
    try {
        return fs.statSync(d).isDirectory();
    }
    catch { return false; }
}

const WASMER = {
    volume: 'build-wasmer-fs',
    mounts: ['usr', 'home', 'etc'],
    flags: ['--stack-size=' + (process.env.WASMER_STACK_SIZE || platform.wasmerStackSize)],
    env: {LEAN_NUM_THREADS: process.env.LEAN_NUM_THREADS || process.env.J || '2'}
}

async function runCommand(cmd: string, args: string[], options: SpawnOptions = {}) {
    console.log(cmd, args.join(' '));
    let p = spawn(cmd, args, {stdio: 'inherit', ...options});

    return await new Promise((resolve, reject) => {
        p.on('exit', (code, signal) => {
            if (code === 0) resolve(code);
            else reject(new Error(`${cmd} failed (${signal ?? code})`));
        });
        p.on('error', reject)
    })
}

async function runWasmer(cwd: string, wasm: string, args: string[]) {
    const w = WASMER;

    return await runCommand('wasmer', ['run', ...w.flags,
        ...w.mounts.flatMap(d => ['--volume', `${path.join(w.volume, d)}:/${d}`]),
        ...Object.entries(w.env).flatMap(([k,v]) => ['--env', `${k}=${v}`]),
        '--cwd', cwd,
        wasm, '--', ...args]);
}

async function main() {

    const program = new Command();

    program
      .name('Builder Bob')
      .argument('<srcdir>', 'source directory')
      .argument('<target>', 'name of Lake target to build')
      .option('-c, --clean', 'clean `.lake` directory before build')
      .option('-k, --continue', 'continue from previous build (do not copy source)')
      .option('-d, --subdir <DIR>', 'build subdirectory (if not at root)')
      .option('-t, --destdir <DIR>', 'where to place files within the Wasmer FS')
      .option('--force-toml', 'translate configs to `toml` format before build')
      .parse();

    let [srcdir, target] = program.args, o = program.opts(),
        destdir = o.destdir ?? path.basename(srcdir);

    if (destdir[0] !== '/') destdir = path.join('/home', destdir);

    let destvol = path.join(WASMER.volume, destdir);

    if (!o.continue) {
        console.log(`${srcdir} --> ${destdir}`);
        fs.emptyDirSync(destvol)
        await copyDirSkippingLake(srcdir, destvol);
    }
    if (o.clean)
        fs.rmSync(path.join(destvol, '.lake'), {recursive: true});

    let builddir = o.subdir ? path.join(destdir, o.subdir) : destdir,
        buildvol = path.join(WASMER.volume, builddir);

    if (o.forceToml)
        await translateConfigs(destvol);

    await shrinkwrap(buildvol, o.forceToml);

    await runWasmer(builddir, 'bin/lake.wasm', [
        '--no-ansi', 'build', '--no-cache', '--packages=lake-manifest.json', target+':leanArts'
    ])

    await packBuiltArtifacts(buildvol);
}

if (process.argv[1] && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url)
    main().catch(error => { console.error(error); process.exitCode = 1; });
