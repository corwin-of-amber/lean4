#include <cstdlib>
#include <iostream>
#include <fstream>
#include <map>

// exception launch pad stub
extern "C"
char __wasm_lpad_context[128];

// function usage count
static struct {
    std::map<std::string, size_t> counters;
    bool init;
    bool enabled;
} cov = {.init = false, .enabled = false};

void atexit_handler_report()
{
    char *outfn = std::getenv("LEAN_COV");
    if (outfn) {
        std::cerr << "[cov] dumping " << outfn << std::endl;

        std::ofstream outf(outfn);
        for (auto it = cov.counters.begin(); it != cov.counters.end(); it++) {
            outf << it->first << " " << it->second << std::endl;
        }
    }
}


extern "C"
void increment_call_count(const char *func) {
    if (!cov.init) {
        cov.init = true;
        cov.enabled = (std::getenv("LEAN_COV") != NULL);
        std::atexit(atexit_handler_report);
    }

    if (cov.enabled) {
        cov.counters[func] += 1;
    }
}

