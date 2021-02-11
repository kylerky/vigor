#ifndef NFOS_MULTIBOOT2_H
#define NFOS_MULTIBOOT2_H

#include <stdint.h>
#include <stdbool.h>

#include "nfos_acpi.h"
#include "nfos_utils.h"

typedef struct nfos_multiboot2_header {
  uint32_t total_size;
  uint32_t reserved;
} PACKED nfos_multiboot2_header_t;

typedef struct nfos_multiboot2_tag {
  uint32_t type;
  uint32_t size;
} PACKED nfos_multiboot2_tag_t;

typedef struct nfos_multiboot2_memory {
  uint32_t type;
  uint32_t size;
  uint32_t mem_lower;
  uint32_t mem_upper;
} PACKED nfos_multiboot2_memory_t;

typedef struct nfos_multiboot2_new_rsdp {
  uint32_t type;
  uint32_t size;
  nfos_rsdp_v2_t rsdp;
} PACKED nfos_multiboot2_new_rsdp_t;

typedef struct nfos_multiboot2_old_rsdp {
  uint32_t type;
  uint32_t size;
  nfos_rsdp_v1_t rsdp;
} PACKED nfos_multiboot2_old_rsdp_t;

enum nfos_multiboot2_types {
  NFOS_MULTIBOOT2_END = 0,
  NFOS_MULTIBOOT2_MEMORY = 4,
  NFOS_MULTIBOOT2_OLD_RSDP = 14,
  NFOS_MULTIBOOT2_NEW_RSDP = 15,
};

bool nfos_get_boot_info(nfos_multiboot2_header_t *mb2_header,
                        boot_info_t *info);

#endif // NFOS_MULTIBOOT2_H
