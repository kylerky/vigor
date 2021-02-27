#ifndef NFOS_BOOT_INFO_H
#define NFOS_BOOT_INFO_H
#include <stddef.h>
#include <stdint.h>

#include "nfos_utils.h"

typedef struct nfos_cpu_info {
  uint32_t apic_id;
  uint32_t node_id;
  uint32_t core_id;
} nfos_cpu_info_t;

typedef struct nfos_node_info {
  uint32_t id;

  uint32_t cpus[MAX_CPUS];
  size_t num_cpus;
} nfos_node_info_t;

typedef struct boot_info {
  uint32_t mem_lower;

  nfos_cpu_info_t cpus[MAX_CPUS];
  size_t num_cpus;

  nfos_node_info_t nodes[MAX_NODES];
  size_t num_nodes;
} nfos_boot_info_t;

extern nfos_boot_info_t boot_info;

#endif // NFOS_BOOT_INFO_H
