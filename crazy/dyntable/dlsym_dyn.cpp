
#include "crc.h"

struct entry { uint32_t k; void *p; };
extern "C" struct entry __dyn_table[];

#define DYN_TABLE_MAX 150000
#define CRC_WIDTH 32
#define CRC_POLY 0x629F6FBF
#define CRC_INIT 0xffffffff

static crc_t crc;
static bool crc_initd = false;

void *dlsym_dyn(const char * sym) {
    if (!crc_initd) {
        crc_init(&crc, CRC_WIDTH, CRC_POLY, CRC_INIT);
        crc_initd = true;
    }

    auto k = crc_string(&crc, sym);
    for (int i = 0; i < DYN_TABLE_MAX; i++) {
        auto& e = __dyn_table[i];
        if (e.k == 0) break;
        if (e.k == k) return e.p;
    }
    return nullptr;
}
