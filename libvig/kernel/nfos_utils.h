#ifndef NFOS_UTILS_H
#define NFOS_UTILS_H

#define PACKED __attribute__((packed))
#define PTR_ADVANCE_BYTES(p, n) (__typeof__(p))(((uintptr_t)(p)) + (n))

#define MAX_CPUS 32

#endif // NFOS_UTILS_H
