#ifndef NFOS_BOOT_INFO_H
#define NFOS_BOOT_INFO_H
#include <stddef.h>
#include <stdint.h>

#include "nfos_utils.h"

typedef struct boot_info {
  uint32_t mem_lower;
  uint8_t cpus[MAX_CPUS];
  size_t num_cpus;
} boot_info_t;

#endif // NFOS_BOOT_INFO_H
