#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <stdbool.h>

#include "nfos_acpi.h"
#include "nfos_boot_info.h"
#include "nfos_utils.h"

static void get_cpus_old(nfos_rsdt_t *rsdt, boot_info_t *info);
static void get_cpus(nfos_xsdt_t *xsdt, boot_info_t *info);
static bool read_table(nfos_sdt_header_t *header, boot_info_t *info);

uint8_t nfos_acpi_checksum(void *ptr, size_t len) {
  uint8_t sum = 0;

  uint8_t *ptr_u8 = (uint8_t *)ptr;
  uint8_t *ptr_end = ptr_u8 + len;
  for (; ptr_u8 < ptr_end; ++ptr_u8) {
    sum += *ptr_u8;
  }
  return sum;
}

void nfos_acpi_parse_rsdp(void *p, boot_info_t *info) {
  nfos_rsdp_v2_t *rsdp = (nfos_rsdp_v2_t *)p;
  uint8_t checksum = NFOS_ACPI_CHECKSUM_STRUCT(&rsdp->first);
  if (checksum != 0) {
    return;
  }
  if (rsdp->first.revision < 2) {
    get_cpus_old((nfos_rsdt_t *)(uintptr_t)rsdp->first.rsdt_address, info);
    return;
  }
  checksum = NFOS_ACPI_CHECKSUM_STRUCT(&rsdp->second);
  if (checksum != 0) {
    return;
  }
  get_cpus((nfos_xsdt_t *)(uintptr_t)rsdp->second.xsdt_address, info);
}

static void get_cpus_old(nfos_rsdt_t *rsdt, boot_info_t *info) {
  uint8_t checksum = nfos_acpi_checksum(rsdt, rsdt->header.length);
  if (checksum != 0) {
    return;
  }

  size_t len =
      (rsdt->header.length - sizeof(rsdt->header)) / sizeof(rsdt->entries[0]);
  for (size_t i = 0; i < len; ++i) {
    nfos_sdt_header_t *header =
        (nfos_sdt_header_t *)(uintptr_t)rsdt->entries[i];
    if (read_table(header, info)) {
      break;
    }
  }
}

static void get_cpus(nfos_xsdt_t *xsdt, boot_info_t *info) {
  uint8_t checksum = nfos_acpi_checksum(xsdt, xsdt->header.length);
  if (checksum != 0) {
    return;
  }

  size_t len =
      (xsdt->header.length - sizeof(xsdt->header)) / sizeof(xsdt->entries[0]);
  for (size_t i = 0; i < len; ++i) {
    nfos_sdt_header_t *header =
        (nfos_sdt_header_t *)(uintptr_t)xsdt->entries[i];
    if (read_table(header, info)) {
      break;
    }
  }
}

static bool read_table(nfos_sdt_header_t *header, boot_info_t *info) {
  if (memcmp(header->signature, "APIC", sizeof(header->signature)) != 0 ||
      nfos_acpi_checksum(header, header->length) != 0) {
    return false;
  }
  nfos_madt_header_t *madt = (nfos_madt_header_t *)header;

  nfos_madt_ic_header_t *ic = (nfos_madt_ic_header_t *)(madt + 1);
  size_t ic_len = madt->header.length - sizeof(*madt);
  nfos_madt_ic_header_t *ic_end = PTR_ADVANCE_BYTES(ic, ic_len);
  while (ic < ic_end) {
    if (ic->type == NFOS_ACPI_IC_PROCESSOR_APIC) {
      nfos_madt_processor_t *cpu = (nfos_madt_processor_t *)ic;
      if (cpu->flags != 1) {
        continue;
      }

      info->cpus[info->num_cpus] = cpu->apic_id;
      ++info->num_cpus;
      if (info->num_cpus >= MAX_CPUS) {
        break;
      }
    }
    ic = PTR_ADVANCE_BYTES(ic, ic->length);
  }

  return true;
}
