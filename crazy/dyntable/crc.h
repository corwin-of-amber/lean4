#ifndef CRC_H
#define CRC_H

#include <stddef.h>
#include <stdint.h>
#include <string.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    uint64_t table[256];
    uint64_t mask;
    uint64_t init;
    unsigned width;   /* 8..64 */
    unsigned shift;   /* width - 8 */
} crc_t;

/* Build the byte table. `poly` omits the implicit x^width term. */
void crc_init(crc_t *c, unsigned width, uint64_t poly, uint64_t init);

/* Same, with the register initialised to all ones (the recommended default). */
void crc_init_ones(crc_t *c, unsigned width, uint64_t poly);

uint64_t crc_bytes(const crc_t *c, const void *data, size_t len);
uint64_t crc_string(const crc_t *c, const char *s);

#ifdef __cplusplus
}
#endif

#endif /* CRC_H */
