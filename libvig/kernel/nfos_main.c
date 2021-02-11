#include <assert.h>
#include <stdlib.h>
#include <stddef.h>
#include <stdio.h>

#include "nfos_boot_info.h"
#include "nfos_pci.h"
#include "nfos_halt.h"
#include "nfos_serial.h"
#include "nfos_multiboot2.h"

extern void _init(void);
extern void do_map_test(void);

/* Kernel main */
extern int main(nfos_multiboot2_header_t *mb_hdr);
/* NF main */
extern int nf_main(int argc, char *argv[]);
/* Initialize filesystem */
extern void stub_stdio_files_init(struct nfos_pci_nic *devs, int n);

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

  printf("ptr: %p\n"
         "size: %u\n"
         "reserved: %x\n",
         mb2_hdr, mb2_hdr->total_size, mb2_hdr->reserved);
  bool success = nfos_get_boot_info(mb2_hdr, &boot_info);
  printf("success %d\n", success);
  printf("lower %lu\n", boot_info.mem_lower);
  printf("num_cpus %lu\n", boot_info.num_cpus);
  for (size_t i = 0; i < boot_info.num_cpus; ++i) {
    printf("cpu %u", boot_info.cpus[i]);
  }
  abort();

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

int nfos_ap_main(void) {
  printf("Done\n");
  return 0;
}
