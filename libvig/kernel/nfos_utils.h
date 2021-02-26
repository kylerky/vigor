#ifndef NFOS_UTILS_H
#define NFOS_UTILS_H

#include <stdint.h>
#define PACKED __attribute__((packed))
#define PTR_ADVANCE_BYTES(p, n) (__typeof__(p))(((uintptr_t)(p)) + (n))

#define MAX_CPUS 32

static inline void x86_wrmsr(const uint32_t reg, const uint32_t high,
                             const uint32_t low) {
  asm volatile("wrmsr" ::"c"(reg), "d"(high), "a"(low));
}

#endif // NFOS_UTILS_H
