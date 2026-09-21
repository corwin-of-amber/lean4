import fs from 'fs-extra';
import path from 'path';
import { spawn, SpawnOptions } from 'child_process';
import { Command } from 'commander';


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

    const lake = path.resolve("bin/lake");

    for (let fn of lakefiles) {
        let subdir = path.dirname(path.resolve(dir, fn));
        console.log(subdir);
        runCommand(lake, ["translate-config", "toml"], {cwd: subdir});
    }
}

async function shrinkwrap(dir: string) {
    let manifests =
        (await fs.readdir(dir, {recursive: true, encoding: 'utf-8'}))
        .filter(fn => path.basename(fn) == 'lake-manifest.json');

    let rootPkgDir = '.lake/packages';

    let toPathType = (pkgDir: string, pkg: any) =>
        pkg.type === 'path' ? pkg : {
            type: 'path',
            scope: pkg.scope,
            name: pkg.name,
            manifestFile: pkg.manifestFile,
            inherited: pkg.inherited,
            dir: path.join(pkgDir, pkg.name, pkg.subdir ?? ''),
            configFile: pkg.configFile
        };

    let withToml = (pkg: any) => ({...pkg, configFile: 'lakefile.toml'});

    for (let fn of manifests) {
        let fp = path.join(dir, fn),
            manifest = JSON.parse(fs.readFileSync(fp, {encoding: 'utf-8'})),
            pkgDir = path.relative(path.dirname(fn), rootPkgDir);

        if (manifest.packages) {
            manifest.packages = manifest.packages
                .map((pkg: any) => toPathType(pkgDir, withToml(pkg)));
            fs.writeFileSync(fp, JSON.stringify(manifest, null, 1));
        }
    }
}

async function packBuiltArtifacts(dir: string) {
    let buildDirs =
        (await fs.readdir(dir, {recursive: true, encoding: 'utf-8'}))
        .filter(fn => fn.endsWith('/build/lib/lean'));

    let stagingDir = '/tmp/bob-staging', exts = ['.olean', '.ir'],
        outFn = 'bob.tar';
    fs.emptyDirSync(stagingDir);
    fs.mkdirSync(stagingDir, {recursive: true});

    // Copy files to `stagingDir`
    for (let d of buildDirs) {
        console.log(d, '-->', stagingDir);
        await fs.copy(path.join(dir, d), stagingDir, {
            filter: src => isDir(src) || exts.some(s => src.endsWith(s))
        });
    }

    let files = fs.readdirSync(stagingDir); /* this is to avoid leading `./` */
    if (files.length > 0)
        await runCommand('tar', ['cf', outFn, '-C', stagingDir, ...files]);

    fs.rm(stagingDir, {recursive: true}); // async
}

function isDir(d: string) {
    try {
        return fs.statSync(d).isDirectory();
    }
    catch { return false; }
}

const WASMER = {
    volume: 'build-wasmer-fs',
    mounts: ['usr', 'home', 'etc', 'dev'],
    flags: ['--stack-size=4000000'],
    env: {LEAN_NUM_THREADS: 2}
}

async function runCommand(cmd: string, args: string[], options: SpawnOptions = {}) {
    console.log(cmd, args.join(' '));
    let p = spawn(cmd, args, {stdio: 'inherit', ...options});

    return await new Promise((resolve, reject) => {
        p.on('exit', resolve);
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

    await translateConfigs(destvol);

    await shrinkwrap(buildvol);

    await runWasmer(builddir, 'bin/lake.wasm', ['build', target+':leanArts'])

    await packBuiltArtifacts(buildvol);
}

main();
