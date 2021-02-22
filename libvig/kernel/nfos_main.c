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
#include "nfos_xapic.h"

#define PAGE_SIZE_BITS 12
// page aligned
#define AP_INIT_CODE_ADDRESS (1 << 12)

extern void _init(void);
extern void do_map_test(void);

/* Kernel main */
extern int main(nfos_multiboot2_header_t *mb2_hdr);
/* NF main */
extern int nf_main(int argc, char *argv[]);
/* Initialize filesystem */
extern void stub_stdio_files_init(struct nfos_pci_nic *devs, int n);

extern volatile uint32_t nfos_ap_index;
volatile uint32_t nfos_ap_index = 1;

extern void ap_init_start(void);
extern void ap_init_end(void);

static bool copy_ap_init_code(void *dest, boot_info_t *info);

#ifdef VIGOR_MODEL_HARDWARE
extern struct nfos_pci_nic *stub_hardware_get_nics(int *n);
#endif

int main(nfos_multiboot2_header_t *mb2_hdr) {
  static char *argv[] = {
    NF_ARGUMENTS,
    NULL,
  };

  static const int argc = (sizeof(argv) / sizeof(argv[0])) - 1;
  static boot_info_t boot_info = {};

#ifndef KLEE_VERIFICATION
  nfos_serial_init();
#endif //! KLEE_VERIFICATION

  if (!nfos_get_boot_info(mb2_hdr, &boot_info)) {
    printf("Failed to parse Multiboot2 boot information\n");
    abort();
  }

  if (!copy_ap_init_code((void *)AP_INIT_CODE_ADDRESS, &boot_info)) {
    printf("Failed to copy AP initialization code to lower memory\n");
    abort();
  }

  while (nfos_ap_index < boot_info.num_cpus) {
    uint8_t current_ap_index = nfos_ap_index;
    uint8_t cpu_id = boot_info.cpus[current_ap_index];
    printf("Starting cpu with APIC id %u\n", cpu_id);

    asm volatile("mfence" ::: "memory");
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

  stub_stdio_files_init(devs, num_devs);

#ifndef KLEE_VERIFICATION
  _init();
#endif //! KLEE_VERIFICATION

  printf("Calling NF...\n");
  nf_main(argc, argv);
  printf("Done\n");

  return 0;
}

static bool copy_ap_init_code(void *dest, boot_info_t *info) {
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

int nfos_ap_main(void) {
  printf("ap_main\n");
  ++nfos_ap_index;
  nfos_halt();
  return 0;
}
