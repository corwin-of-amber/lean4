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

    *buddies() {
        for (let mo of this.text.matchAll(/^\S+ (\S+?)\(.*\nLEAN_EXPORT lean_object\s*\*\s*(\S+?__boxed)\(/mg))
            yield {plain: mo[1], boxed: mo[2]};
    }
}

class GlobalDataSweeper {
    constructor(public text: string) {
    }

    *inited() {
        for (let mo of this.text.matchAll(/^\S+ = lean_io_result.*\nlean_mark_persistent\((\S+?)\)/mg))
            yield {sym: mo[1]};
    }
}



/** This is not a full list! */
const MODULES_WITH_EXTERNS = [
    'Init/Prelude',
    'Init/Data/Repr',
    'Init/Data/Nat/Gcd', 'Init/Data/Nat/Bitwise/Basic', 'Init/Data/Nat/Div/Basic',
    'Init/Data/Int/Basic', 'Init/Data/Int/DivMod/Basic',
    'Init/Data/UInt/Basic', 'Init/Data/UInt/BasicAux',
    'Init/Data/SInt/Basic',
    'Init/Data/Array/Basic', 'Init/Data/Array/Set', 'Init/Data/ByteArray/Basic',
    'Init/Data/String/Basic', 'Init/Data/String/Defs', 'Init/Data/String/Search', 'Init/Data/String/Bootstrap', 'Init/Data/String/PosRaw', 'Init/Data/String/Pattern/Basic',
    'Init/System/IO',
    'Init/System/ST',
    'Init/Util'
];

const MODULES_WITH_INITED = fs.readFileSync('/tmp/a', 'utf-8').trim().split('\n');

const ROOT_C_DIR = 'build/release/stage1/lib/temp'

const EXTRA = ['l_Lean_Parser_categoryParserFnExtension', 'l___private_Lean_ImportingFlag_0__Lean_importingRef']

function main() {
    for (let fn of MODULES_WITH_EXTERNS) {
        let sw = Sweeper.fromFile(path.join(ROOT_C_DIR, `${fn}.c`));

        for (let it of sw.func.buddies())
            process.stdout.write(`-Wl,--export=${it.boxed}\n`);
    }

    for (let fn of MODULES_WITH_INITED) {
        let sw = Sweeper.fromFile(path.join(ROOT_C_DIR, `${fn}.c`));

        for (let it of sw.glob.inited())
            process.stdout.write(`-Wl,--export=${it.sym}\n`);
        //for (let k of EXTRA) {
        //    process.stdout.write(`-Wl,--export=${k}\n`);
        //}
    }
}

main();
