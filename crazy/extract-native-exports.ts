/**
 * This is a "best effort" (by no means best) to collect the names of
 * symbols that need to be exported from the Lean executable.
 * In particular, boxed versions of native C implementations that have
 * no non-native counterpart.
 *
 * While other native-compiled Lean implementations can benefit in
 * terms of performance from having their boxed version exported,
 * the native-only ones are those that cause a fatal error in case
 * they are missing. OTOH, exporting all symbols induces a very large
 * exports table that, unfortunately, blows up the WASM binary.
 * Therefore a conservative compromise is to only export the essential
 * ones.
 *
 * Native-only exports are detected via this heuristic pattern (in
 * the C files produced by the Lean compiler):
 * ```
 * uint8_t lean_uint8_of_nat_mk(lean_object*);
 * LEAN_EXPORT lean_object* l_UInt8_ofBitVec___boxed(lean_object*);
 * ```
 * The first line is the C implementation; the second is the boxed
 * variant.
 *
 * Native data with attached initializers take this form:
 * ```
 * l_Lean_Parser_categoryParserFnExtension = lean_io_result_get_value(res);
 * lean_mark_persistent(l_Lean_Parser_categoryParserFnExtension);
 * ```
 */
import fs from 'fs';
import path from 'path';

import { makeCrc } from './dyntable/crc';

class Sweeper {
    func: FunctionSweeper
    glob: GlobalDataSweeper

    constructor(public text: string) {
        this.func = new FunctionSweeper(text);
        this.glob = new GlobalDataSweeper(text);
    }

    static fromFile(fn: string) {
        return new Sweeper(fs.readFileSync(fn, 'utf-8'));
    }
}

class FunctionSweeper {
    constructor(public text: string) {
    }

    *prototypes() {
        for (let mo of this.text.matchAll(/^LEAN_EXPORT (lean_object\s*\*\s*(\S+?__boxed|runtime_initialize_\S+?|initialize_\S+?)\(.*\))\s*[;{]/mg))
            if (!mo[2].includes('0'))
                yield {sig: mo[1], name: mo[2]}
    }

    *buddies() {
        for (let mo of this.text.matchAll(/^\S+ (\S+?)\(.*\nLEAN_EXPORT lean_object\s*\*\s*(\S+?__boxed)\(/mg))
            yield {plain: mo[1], boxed: mo[2]};
    }
}

class GlobalDataSweeper {
    constructor(public text: string) {
    }

    *prototypes() {
        for (let mo of this.text.matchAll(/^LEAN_EXPORT (lean_object\s*\*\s*([_\w]*));/mg))
            yield {sig: mo[1], name: mo[2]}
    }

    *inited() {
        for (let mo of this.text.matchAll(/^\S+ = lean_io_result.*\nlean_mark_persistent\((\S+?)\)/mg))
            yield {sym: mo[1]};
    }
}



/** This is not a full list! */
const MODULES_WITH_EXTERNS = [
    'Init/Prelude',
    'Init/Core',
    'Init/Data/Repr',
    'Init/Data/Nat/Gcd', 'Init/Data/Nat/Bitwise/Basic', 'Init/Data/Nat/Div/Basic',
    'Init/Data/Int/Basic', 'Init/Data/Int/DivMod/Basic',
    'Init/Data/UInt/Basic', 'Init/Data/UInt/BasicAux',
    'Init/Data/SInt/Basic',
    'Init/Data/Array/Basic', 'Init/Data/Array/Set', 'Init/Data/ByteArray/Basic',
    'Init/Data/String/Basic', 'Init/Data/String/Defs', 'Init/Data/String/Search', 'Init/Data/String/Bootstrap', 'Init/Data/String/PosRaw', 'Init/Data/String/Pattern/Basic',
    'Init/Data/Ord/String',
    'Init/System/IO',
    'Init/System/ST',
    'Init/Task',
    'Init/Util',
    'Lean/Util/Profile'
];

const MODULES_WITH_INITED = []; //fs.readFileSync('/tmp/a', 'utf-8').trim().split('\n');

const ROOT_C_DIR = 'build/release/stage1/lib/temp'
//const ROOT_C_DIR = 'build/release/stage1/lib/temp/Init/Data/String/Pattern'

const EXTRA = ['l_Lean_Parser_categoryParserFnExtension', 'l___private_Lean_ImportingFlag_0__Lean_importingRef']

function allCFiles(dir: string) {
    return fs.readdirSync(dir, {recursive: true, encoding: 'utf-8'})
             .filter(f => f.endsWith('.c'));
}

function *chain<T>(...iterables: Iterable<T>[]) {
    for (let it of iterables) yield* it;
}

const EXCEPT = ['LeanIR.c', 'LeanChecker.c', 'Leanc.c', 'LakeMain.c'];

function *procession(tbl: Set<string>, max: number) {
    for (let fn of allCFiles(ROOT_C_DIR)) {
        if (!fn.endsWith('.c')) fn += '.c';
        if (EXCEPT.includes(fn)) continue;

        let sw = Sweeper.fromFile(path.join(ROOT_C_DIR, fn));

        for (let it of chain(sw.func.prototypes(), sw.glob.prototypes())) {
            if (!tbl.has(it.name)) {
                tbl.add(it.name);
                yield it;
            }
            if (tbl.size >= max) return;
        }
    }
}

function extractAsLinkFlags(out: any, max: number) {
    let tbl = new Set<string>();

    for (let it of procession(tbl, max)) {
        out.write(`-Wl,--export=${it.name}\n`);
    }

    process.stderr.write(`[info] # symbols: ${tbl.size}\n`);
}

function extractAsCTable(out: any, max: number) {
    let tbl = new Set<string>();

    out.write(`#include "lean/lean.h"\n\n`)

    for (let it of procession(tbl, max)) {
        out.write(`extern ${it.sig} __attribute__((weak_import));\n`);
    }

    let crc = makeCrc(32, 0x629F6FBF), ctbl = new Set<number>();

    out.write(`\n\nstruct entry { uint32_t k; void *p; };\n`)
    out.write(`\nLEAN_EXPORT struct entry __dyn_table[] = {\n    `)
    for (let nm of tbl) {
        let k = crc.ascii(nm);
        ctbl.add(k);
        out.write(`{0x${k.toString(16)}, &${nm}},`);
    }
    out.write(`\n     {0, 0}\n};\n`);

    process.stderr.write(`[info] # symbols: ${tbl.size}\n`);

    // Sanity
    if (ctbl.size != tbl.size)
        throw new Error("CRC collision");
}

function main() {
    let out = process.stdout, max = 70000;

    for (let arg of process.argv) {
        switch (arg) {
            case 'link':
                extractAsLinkFlags(out, max); break;
            case 'dyn':
                extractAsCTable(out, max); break;
        }
    }

    // wasi-kit clang -Isrc -Isrc/include -Icrazy/include -include lean/lean.h -c out.c
}

main();
