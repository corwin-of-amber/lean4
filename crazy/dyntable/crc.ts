/**
 * MSB-first table-driven CRC (Galois LFSR with the message XORed into the
 * feedback path). Matches the convention used by the search script:
 *
 *   - `poly` omits the implicit x^width term
 *   - register starts at all-ones
 *   - bytes are fed most-significant-bit first
 *   - no input/output reflection, no final XOR
 *
 * Widths 8..32 use plain numbers; 33..64 use BigInt.
 */

export interface Crc {
  readonly width: number;
  /** CRC of raw bytes. */
  bytes(data: Uint8Array): number;
  /** CRC of an ASCII string (code points above 0x7F will throw). */
  ascii(s: string): number;
}

export interface Crc64 {
  readonly width: number;
  bytes(data: Uint8Array): bigint;
  ascii(s: string): bigint;
}

function asciiBytes(s: string): Uint8Array {
  const out = new Uint8Array(s.length);
  for (let i = 0; i < s.length; i++) {
    const c = s.charCodeAt(i);
    if (c > 0x7f) {
      throw new RangeError(`non-ASCII code point ${c} at index ${i}`);
    }
    out[i] = c;
  }
  return out;
}

/** Width 8..32. `poly` and `init` are numbers; `init` defaults to all-ones. */
export function makeCrc(width: number, poly: number, init?: number): Crc {
  if (!Number.isInteger(width) || width < 8 || width > 32) {
    throw new RangeError("width must be an integer in 8..32");
  }
  const mask = (2 ** width - 1) >>> 0;
  const top = 2 ** (width - 1);
  const shift = width - 8;
  const p = poly >>> 0;
  const start = ((init === undefined ? mask : init) & mask) >>> 0;

  const table = new Uint32Array(256);
  for (let b = 0; b < 256; b++) {
    let r = ((b << shift) & mask) >>> 0;
    for (let k = 0; k < 8; k++) {
      r = (r & top ? ((r << 1) ^ p) & mask : (r << 1) & mask) >>> 0;
    }
    table[b] = r;
  }

  function bytes(data: Uint8Array): number {
    let r = start;
    for (let i = 0; i < data.length; i++) {
      r = ((((r << 8) & mask) ^ table[((r >>> shift) ^ data[i]) & 0xff]) >>> 0);
    }
    return r;
  }

  return { width, bytes, ascii: (s) => bytes(asciiBytes(s)) };
}

/** Width 8..64 using BigInt. Use this when width > 32. */
export function makeCrcBig(width: number, poly: bigint, init?: bigint): Crc64 {
  if (!Number.isInteger(width) || width < 8 || width > 64) {
    throw new RangeError("width must be an integer in 8..64");
  }
  const w = BigInt(width);
  const mask = (1n << w) - 1n;
  const top = 1n << (w - 1n);
  const shift = w - 8n;
  const p = poly & mask;
  const start = (init === undefined ? mask : init) & mask;

  const table = new BigUint64Array(256);
  for (let b = 0; b < 256; b++) {
    let r = (BigInt(b) << shift) & mask;
    for (let k = 0; k < 8; k++) {
      r = (r & top) !== 0n ? ((r << 1n) ^ p) & mask : (r << 1n) & mask;
    }
    table[b] = r;
  }

  function bytes(data: Uint8Array): bigint {
    let r = start;
    for (let i = 0; i < data.length; i++) {
      r = ((r << 8n) & mask) ^ table[Number((r >> shift) & 0xffn) ^ data[i]];
    }
    return r;
  }

  return { width, bytes, ascii: (s) => bytes(asciiBytes(s)) };
}
