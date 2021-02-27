#include <assert.h>
#include <stdint.h>
#include <stdlib.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>
#include <stdbool.h>

#include "nfos_boot_info.h"
#include "nfos_pci.h"
#include "nfos_halt.h"
#include "nfos_serial.h"
#include "nfos_multiboot2.h"
#include "nfos_utils.h"
#include "nfos_xapic.h"

#define PAGE_SIZE_BITS 12
// page aligned
#define AP_INIT_CODE_ADDRESS (1 << 12)

extern void _init(void);
extern void do_map_test(void);

/* Kernel main */
extern int main(nfos_multiboot2_header_t *mb2_hdr, uint32_t apic_id,
                uint32_t num_bit_thread, uint32_t num_bit_core);
/* NF main */
extern int nf_main(int argc, char *argv[]);
/* Initialize filesystem */
extern void stub_stdio_files_init(struct nfos_pci_nic *devs, int num_devs,
                                  nfos_boot_info_t *info);

// multiprocessors initialization helpers
extern void ap_init_start(void);
extern void ap_init_end(void);

static bool copy_ap_init_code(void *dest, nfos_boot_info_t *info);

static bool fill_node_id(nfos_boot_info_t *info);
static uint32_t apic_to_cpu_index(nfos_boot_info_t *info, uint32_t apic);

#ifdef VIGOR_MODEL_HARDWARE
extern struct nfos_pci_nic *stub_hardware_get_nics(int *n);
#endif

extern volatile uint32_t nfos_ap_index;
volatile uint32_t nfos_ap_index = 1;

nfos_boot_info_t boot_info = {};

static inline void fill_cpu_id(uint32_t index, uint32_t apic_id,
                               uint32_t num_bit_thread, uint32_t num_bit_core);

int main(nfos_multiboot2_header_t *mb2_hdr, uint32_t apic_id,
         uint32_t num_bit_thread, uint32_t num_bit_core) {
  static char *argv[] = {
    NF_ARGUMENTS,
    NULL,
  };

  static const int argc = (sizeof(argv) / sizeof(argv[0])) - 1;

#ifndef KLEE_VERIFICATION
  nfos_serial_init();
#endif //! KLEE_VERIFICATION

  if (!nfos_get_boot_info(mb2_hdr, &boot_info)) {
    printf("Failed to parse Multiboot2 boot information\n");
    abort();
  }

  if (!fill_node_id(&boot_info)) {
    printf("Error detecting NUMA topology\n");
    abort();
  }

  fill_cpu_id(0, apic_id, num_bit_thread, num_bit_core);

  if (!copy_ap_init_code((void *)AP_INIT_CODE_ADDRESS, &boot_info)) {
    printf("Failed to copy AP initialization code to lower memory\n");
    abort();
  }

  while (nfos_ap_index < boot_info.num_cpus) {
    uint32_t current_ap_index = nfos_ap_index;
    uint32_t cpu_id = boot_info.cpus[current_ap_index].apic_id;
    printf("Starting cpu with APIC id %u\n", cpu_id);

    x86_mfence();
    nfos_apic_send_init(cpu_id);
    nfos_apic_send_sipi(cpu_id, AP_INIT_CODE_ADDRESS >> PAGE_SIZE_BITS);

    while (current_ap_index == nfos_ap_index) {
    }
  }

  int num_devs;
  struct nfos_pci_nic *devs;

#ifdef VIGOR_MODEL_HARDWARE
  devs = stub_hardware_get_nics(&num_devs);
#else  // VIGOR_MODEL_HARDWARE
  devs = nfos_pci_find_nics(&num_devs);
#endif // VIGOR_MODEL_HARDWARE

  stub_stdio_files_init(devs, num_devs, &boot_info);

#ifndef KLEE_VERIFICATION
  _init();
#endif //! KLEE_VERIFICATION

  printf("Calling NF...\n");
  nf_main(argc, argv);
  printf("Done\n");

  return 0;
}

static bool copy_ap_init_code(void *dest, nfos_boot_info_t *info) {
  size_t code_size = (size_t)(ap_init_end - ap_init_start);
  size_t mem_lower = info->mem_lower << NFOS_MULTIBOOT2_MEM_LOWER_LSHIFT;
  if (AP_INIT_CODE_ADDRESS + code_size > mem_lower) {
    printf("AP initialisation code does not fit in the lower memory\n"
           "code size: %lu\n",
           code_size);
    return false;
  }

  memcpy(dest, ap_init_start, code_size);
  return true;
}

int nfos_ap_main(uint32_t apic_id, uint32_t num_bit_thread,
                 uint32_t num_bit_core) {
  fill_cpu_id(nfos_ap_index, apic_id, num_bit_thread, num_bit_core);
  ++nfos_ap_index;
  nfos_halt();
  return 0;
}

static inline void fill_cpu_id(uint32_t index, uint32_t apic_id,
                               uint32_t num_bit_thread, uint32_t num_bit_core) {
  boot_info.cpus[index].apic_id = apic_id;
  boot_info.cpus[index].core_id =
      (apic_id >> num_bit_thread) & ~((~((uint32_t)0)) << num_bit_core);
}

static bool fill_node_id(nfos_boot_info_t *info) {
  for (size_t node_idx = 0; node_idx < info->num_nodes; ++node_idx) {
    nfos_node_info_t *node = &info->nodes[node_idx];
    for (size_t cpu_idx = 0; cpu_idx < node->num_cpus; ++cpu_idx) {
      uint32_t index = apic_to_cpu_index(info, node->cpus[cpu_idx]);
      if (index == MAX_CPUS) {
        return false;
      }
      node->cpus[cpu_idx] = index;
      info->cpus[index].node_id = node->id;
    }
  }
  return true;
}

static uint32_t apic_to_cpu_index(nfos_boot_info_t *info, uint32_t apic) {
  for (size_t i = 0; i < info->num_cpus; ++i) {
    if (info->cpus[i].apic_id == apic) {
      return i;
    }
  }
  return MAX_CPUS;
}
