#include <cstdlib>
#include <iostream>
#include <fstream>
#include <map>

#include <uv.h>
#include <unistd.h>
#include <sys/stat.h>


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


extern "C" {

#define STUB(X) std::cerr << "[stub] " << __func__ X << std::endl

const char* uv_strerror(int err) { return strerror(err); }

int uv_fs_stat(uv_loop_t* loop,
               uv_fs_t* req,
               const char* path,
               uv_fs_cb cb) {
    //STUB(<< " " << path);
    struct stat res;
    uv_stat_t& uvres = req->statbuf;
    int rc = stat(path, &res);
    if (rc == 0) {
        uvres.st_dev = res.st_dev;
        uvres.st_ino = res.st_ino;
        uvres.st_mode = res.st_mode;
        uvres.st_nlink = res.st_nlink;
        uvres.st_uid = res.st_uid;
        uvres.st_gid = res.st_gid;
        uvres.st_size = res.st_size;
        uvres.st_blocks = res.st_blocks;
        uvres.st_blksize = res.st_blksize;
        uvres.st_flags = 0;
        uvres.st_gen = 0;
        /*
        uv_timespec_t st_atim;
        uv_timespec_t st_mtim;
        uv_timespec_t st_ctim;
        uv_timespec_t st_birthtim;
        */
    }
    return rc == 0 ? 0 : -errno;
}

void uv_fs_req_cleanup(uv_fs_t* req) { }

int uv_os_tmpdir(char* buffer, size_t* size) { STUB(); return 0; }
int uv_fs_mkdtemp(uv_loop_t* loop,
                  uv_fs_t* req,
                  const char* tpl,
                  uv_fs_cb cb) { STUB(); return 0; }
int uv_fs_mkstemp(uv_loop_t* loop,
                  uv_fs_t* req,
                  const char* tpl,
                  uv_fs_cb cb) { STUB(); return 0; }
int uv_fs_unlink(uv_loop_t* loop,
                 uv_fs_t* req,
                 const char* path,
                 uv_fs_cb cb) { unlink(path); return 0; }

}

int uv_fs_link(uv_loop_t* loop,
                         uv_fs_t* req,
                         const char* path,
                         const char* new_path,
                         uv_fs_cb cb) { STUB(); return 0; }

int uv_fs_lstat(uv_loop_t* loop,
                          uv_fs_t* req,
                          const char* path,
                          uv_fs_cb cb) { STUB(); return 0; }

// exception launch pad stub
#undef __wasm_lpad_context
char __wasm_lpad_context[128];
