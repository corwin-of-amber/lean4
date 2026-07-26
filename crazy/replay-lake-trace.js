import fs from 'fs';
import path from 'path';
import child_process from 'child_process';


function *getFilesFromLakeLog() {
    let txt = fs.readFileSync('tmp/lake-build-init.log', 'utf-8');

    for (let mo of txt.matchAll(/[.]\/src\/(\S+)[.]lean/g)) {
        yield mo[1];
    }
}

function setupFileFor(basename) {
    let txt = fs.readFileSync(`tmp/init/build/lib/temp/${basename}.setup.json`, 'utf-8');

    return txt.replace(/\/\S+\/.\//g, '');
}


function compileOneWithWasmer(basename) {
    const WASM_FS = 'build-wasmer-fs'
    const TEMPLATE = s => `wasmer run --enable-tail-call --stack-size=50000000` +
        ` --volume ${WASM_FS}/home/init:/home/init --volume ${WASM_FS}/dev:/dev` +
        ` --volume ${WASM_FS}/usr:/usr` +
        ` --cwd /home/init --env LEAN_PATH=/home/init/build/lib/lean ./bin/lean.wasm` +
        ` -- -Dbackward.do.legacy=false -s40000 -Dinterpreter.prefer_native=false ` +
        `src/${s}.lean -o build/lib/lean/${s}.olean -i build/lib/lean/${s}.ilean ` +
        `--setup build/lib/temp/${s}.setup.json`;
    fs.mkdirSync(`${WASM_FS}/home/init/build/lib/lean/${path.dirname(basename)}`, {recursive: true});
    fs.mkdirSync(`${WASM_FS}/home/init/build/lib/temp/${path.dirname(basename)}`, {recursive: true});
    fs.writeFileSync(`${WASM_FS}/home/init/build/lib/temp/${basename}.setup.json`, setupFileFor(basename));
    runCommand(TEMPLATE(basename));
}

function runCommand(cmd) {
    console.log('>', cmd);
    try {
        child_process.execSync(cmd, {encoding: 'utf-8', stdio: 'inherit'});
    }
    catch (e) {
        throw new Error(`status: ${e.status}`);
    }
}


function main() {

    const contFrom = 'Init/Data/Vector/Lex';

    let filenames = [...getFilesFromLakeLog()];
    let flag = contFrom === undefined;
    let i = 1, n = filenames.length;

    for (let fn of filenames) {
        console.log(`[${i++}/${n}]`, fn);
        if (fn === contFrom) flag = true;
        if (flag)
            compileOneWithWasmer(fn);
    }
}


main();
