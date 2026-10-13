// D-13: require the actual WasmGC artifact; never fall back to a Native addon.
import { readFile } from 'node:fs/promises';

export async function loadEngineModule(url) {
  let module;
  try {
    const bytes = url ? await readFile(url) : await readFile(new URL('./engine.wasm', import.meta.url)).catch(error => {
      if (error.code !== 'ENOENT') throw error;
      return readFile(new URL('../../target/wasm/engine.wasm', import.meta.url));
    });
    module = await WebAssembly.compile(bytes, { builtins: ['js-string'], importedStringConstants: '_' });
    const imports = WebAssembly.Module.imports(module);
    const unsupported = imports.filter(i => i.module !== '_' || i.kind !== 'global');
    if (unsupported.length) throw new Error(`Unexpected or unsupported imports: ${unsupported.map(i => `${i.module}.${i.name}`).join(', ')}`);
    // Node 22 recognizes JS string builtins but still lists imported constants.
    const strings = Object.create(null);
    for (const item of imports) strings[item.name] = item.name;
    const instance = await WebAssembly.instantiate(module, { _: strings });
    for (const name of ['abi_version', 'configure', 'begin_request', 'complete', 'take_chunk', 'release']) {
      if (typeof instance.exports[name] !== 'function') throw new Error(`Missing export ${name}`);
    }
    if (instance.exports.abi_version() !== 1) throw new Error('Incompatible Wasm bridge version');
    return instance.exports;
  } catch (cause) {
    throw Object.assign(new Error('Cannot load WasmGC engine; build the artifact and use Node 22.21.1 or 24.10.0 with WasmGC/JS string builtins', { cause }), { code: 'HS_UNSUPPORTED' });
  }
}
