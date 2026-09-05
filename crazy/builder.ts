import fs from 'fs-extra';
import path from 'path';
import { spawn } from 'child_process';
import { Command } from 'commander';


async function copyDirSkippingLake(src: string, dest: string) {
    fs.mkdirSync(dest, {recursive: true});
    await fs.copy(src, dest, {
        filter: src => path.basename(src) !== '.lake'
    });
}


const WASMER = {
    volume: 'build-wasmer-fs',
    mounts: ['usr', 'home', 'dev'],
    flags: ['--stack-size=4000000'],
    env: {LEAN_NUM_THREADS: 2}
}

async function runWasmer(cwd: string, wasm: string, args: string[]) {
    const w = WASMER;

    let p = spawn('wasmer', ['run', ...w.flags,
        ...w.mounts.flatMap(d => ['--volume', `${path.join(w.volume, d)}:/${d}`]),
        ...Object.entries(w.env).flatMap(([k,v]) => ['--env', `${k}=${v}`]),
        '--cwd', cwd,
        wasm, '--', ...args], {stdio: 'inherit'});

    return await new Promise((resolve, reject) => {
        p.on('exit', resolve);
        p.on('error', reject)
    })
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

    let builddir = o.subdir ? path.join(destdir, o.subdir) : destdir;

    console.log(
        await runWasmer(builddir, 'bin/lake.wasm', ['build', target+':leanArts'])
    );
}

main();
