/*
 * MSB-first table-driven CRC (Galois LFSR with the message XORed into the
 * feedback path). Matches the convention used by the search script:
 *
 *   - `poly` omits the implicit x^width term
 *   - register starts at all-ones
 *   - bytes are fed most-significant-bit first
 *   - no input/output reflection, no final XOR
 *
 * Supports any width from 8 to 64.
 */

#include "crc.h"

void crc_init(crc_t *c, unsigned width, uint64_t poly, uint64_t init)
{
    c->width = width;
    c->mask  = (width == 64) ? UINT64_MAX : ((UINT64_C(1) << width) - 1);
    c->shift = width - 8;
    c->init  = init & c->mask;

    const uint64_t top = UINT64_C(1) << (width - 1);
    poly &= c->mask;

    for (unsigned b = 0; b < 256; b++) {
        uint64_t r = ((uint64_t)b << c->shift) & c->mask;
        for (unsigned k = 0; k < 8; k++) {
            r = (r & top) ? (((r << 1) ^ poly) & c->mask)
                          : ((r << 1) & c->mask);
        }
        c->table[b] = r;
    }
}

void crc_init_ones(crc_t *c, unsigned width, uint64_t poly)
{
    uint64_t mask = (width == 64) ? UINT64_MAX : ((UINT64_C(1) << width) - 1);
    crc_init(c, width, poly, mask);
}

uint64_t crc_bytes(const crc_t *c, const void *data, size_t len)
{
    const unsigned char *p = (const unsigned char *)data;
    uint64_t r = c->init;

    for (size_t i = 0; i < len; i++) {
        r = ((r << 8) & c->mask) ^ c->table[((r >> c->shift) ^ p[i]) & 0xFF];
    }
    return r;
}

uint64_t crc_string(const crc_t *c, const char *s)
{
    return crc_bytes(c, s, strlen(s));
}
