#include <stdbool.h>
#include <stdio.h>
#include <stdint.h>

#include "nfos_acpi.h"
#include "nfos_multiboot2.h"
#include "nfos_boot_info.h"
#include "nfos_utils.h"

// #define NEXT_TAG(t)                                                            \
//   do {                                                                         \
//     uintptr_t p = (((uintptr_t)(t)) + (t)->size);                   \
//     (t) = (__typeof__(t))((p + 7) & (~((uintptr_t)7)));                        \
//   } while (false)
#define NEXT_TAG(t)                                                            \
  (__typeof__(t))(((((uintptr_t)(t)) + (t)->size) + 7) & (~((uintptr_t)7)))

bool nfos_get_boot_info(nfos_multiboot2_header_t *mb2_header,
                        boot_info_t *info) {
  nfos_multiboot2_tag_t *tag = (nfos_multiboot2_tag_t *)(mb2_header + 1);

  bool mem_done = false;
  bool rsdp_done = false;
  for (; tag->type != NFOS_MULTIBOOT2_END; tag = NEXT_TAG(tag)) {
    switch (tag->type) {
      case NFOS_MULTIBOOT2_MEMORY: {
        nfos_multiboot2_memory_t *mem = (nfos_multiboot2_memory_t *)tag;
        info->mem_lower = mem->mem_lower;
        mem_done = true;
        break;
      }

      case NFOS_MULTIBOOT2_OLD_RSDP:
        if (!rsdp_done) {
          nfos_multiboot2_old_rsdp_t *rsdp_tag =
              (nfos_multiboot2_old_rsdp_t *)tag;
          nfos_acpi_parse_rsdp(&rsdp_tag->rsdp, info);
          rsdp_done = true;
        }
        break;
      case NFOS_MULTIBOOT2_NEW_RSDP: {
        nfos_multiboot2_new_rsdp_t *rsdp_tag =
            (nfos_multiboot2_new_rsdp_t *)tag;
        nfos_acpi_parse_rsdp(&rsdp_tag->rsdp, info);
        rsdp_done = true;
        break;
      }
    }
  }
  return mem_done && rsdp_done;
}
