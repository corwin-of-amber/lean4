/* Test the explicit mimalloc API and cross-thread frees under WASIX. */
#define _POSIX_C_SOURCE 200809L
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <mimalloc.h>

#define CHECK(condition) do { if (!(condition)) { \
  fprintf(stderr, "check failed at line %d: %s\n", __LINE__, #condition); abort(); \
} } while (0)

struct job { void *incoming; void *outgoing; unsigned number; };

static void *worker(void *argument) {
  struct job *job = argument;
  CHECK(mi_is_in_heap_region(job->incoming));
  CHECK(((unsigned char *)job->incoming)[511] == 0x7e);
  mi_free(job->incoming);
  for (unsigned i = 1; i <= 10000; i++) {
    size_t size = 8 + i % 4096;
    unsigned char *p = mi_malloc(size);
    CHECK(p && mi_is_in_heap_region(p) && mi_usable_size(p) >= size);
    memset(p, 0x39, size);
    p = mi_realloc(p, size + 127);
    CHECK(p && mi_is_in_heap_region(p));
    CHECK(p[0] == 0x39 && p[size - 1] == 0x39);
    mi_free(p);
  }
  job->outgoing = mi_malloc(8192);
  CHECK(job->outgoing && mi_is_in_heap_region(job->outgoing));
  memset(job->outgoing, job->number, 8192);
  return NULL;
}

int main(void) {
  unsigned char *zero = mi_calloc(3073, 1);
  CHECK(zero && mi_is_in_heap_region(zero));
  for (size_t i = 0; i < 3073; i++) CHECK(zero[i] == 0);
  mi_free(zero);
  void *aligned = mi_aligned_alloc(64, 4096);
  CHECK(aligned && (uintptr_t)aligned % 64 == 0 && mi_is_in_heap_region(aligned));
  mi_free(aligned);
  CHECK(mi_posix_memalign(&aligned, 128, 8192) == 0);
  CHECK(aligned && (uintptr_t)aligned % 128 == 0 && mi_is_in_heap_region(aligned));
  mi_free(aligned);
  mi_free(NULL);
  void *empty = mi_malloc(0);
  mi_free(empty);
  pthread_t threads[4];
  struct job jobs[4];
  for (unsigned i = 0; i < 4; i++) {
    jobs[i].incoming = mi_malloc(512);
    CHECK(jobs[i].incoming && mi_is_in_heap_region(jobs[i].incoming));
    memset(jobs[i].incoming, 0x7e, 512);
    jobs[i].number = i + 1;
    CHECK(pthread_create(&threads[i], NULL, worker, &jobs[i]) == 0);
  }
  for (unsigned i = 0; i < 4; i++) {
    CHECK(pthread_join(threads[i], NULL) == 0);
    CHECK(((unsigned char *)jobs[i].outgoing)[8191] == i + 1);
    mi_free(jobs[i].outgoing);
  }
  puts("allocator probe passed: malloc/calloc/realloc/alignment and cross-thread frees");
  return 0;
}
