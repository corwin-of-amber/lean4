// Copyright (c) 2026 Emilio Jesus Gallego Arias. All rights reserved.
// Released under Apache 2.0 license as described in the file LICENSE.
import path from 'node:path';

type Dependency = { type: string; name: string; subDir?: string; configFile?: string; [key: string]: unknown };
type Manifest = { packages: Dependency[]; [key: string]: unknown };

/** Convert a resolved graph to local paths without changing the input manifest. */
export function shrinkwrapManifest(manifest: Manifest, packageDirectory: string, toml: boolean): Manifest {
    return { ...manifest, packages: manifest.packages.map(dependency => {
        if (dependency.type === 'path') return { ...dependency, ...(toml ? {configFile: 'lakefile.toml'} : {}) };
        const { subDir, ...fields } = dependency;
        return { type: 'path', scope: fields.scope, name: fields.name,
            manifestFile: fields.manifestFile, inherited: fields.inherited,
            dir: path.join(packageDirectory, fields.name, subDir ?? ''),
            configFile: toml ? 'lakefile.toml' : fields.configFile };
    }) };
}
