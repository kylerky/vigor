#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <stdbool.h>

#include "nfos_acpi.h"
#include "nfos_boot_info.h"
#include "nfos_utils.h"

static void get_cpus_old(nfos_rsdt_t *rsdt, nfos_boot_info_t *info);
static void get_cpus(nfos_xsdt_t *xsdt, nfos_boot_info_t *info);

static bool process_sdt(nfos_sdt_header_t *header, nfos_boot_info_t *info);

static bool read_madt(nfos_sdt_header_t *header, nfos_boot_info_t *info);
static bool read_srat(nfos_sdt_header_t *header, nfos_boot_info_t *info);

static uint32_t get_node_id(nfos_srat_apic_t *apic);

uint8_t nfos_acpi_checksum(void *ptr, size_t len) {
  uint8_t sum = 0;

  uint8_t *ptr_u8 = (uint8_t *)ptr;
  uint8_t *ptr_end = ptr_u8 + len;
  for (; ptr_u8 < ptr_end; ++ptr_u8) {
    sum += *ptr_u8;
  }
  return sum;
}

void nfos_acpi_parse_rsdp(void *p, nfos_boot_info_t *info) {
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

static void get_cpus_old(nfos_rsdt_t *rsdt, nfos_boot_info_t *info) {
  uint8_t checksum = nfos_acpi_checksum(rsdt, rsdt->header.length);
  if (checksum != 0) {
    return;
  }

  size_t len =
      (rsdt->header.length - sizeof(rsdt->header)) / sizeof(rsdt->entries[0]);
  for (size_t i = 0; i < len; ++i) {
    nfos_sdt_header_t *header =
        (nfos_sdt_header_t *)(uintptr_t)rsdt->entries[i];
    if (process_sdt(header, info)) {
      break;
    }
  }
}

static void get_cpus(nfos_xsdt_t *xsdt, nfos_boot_info_t *info) {
  uint8_t checksum = nfos_acpi_checksum(xsdt, xsdt->header.length);
  if (checksum != 0) {
    return;
  }

  size_t len =
      (xsdt->header.length - sizeof(xsdt->header)) / sizeof(xsdt->entries[0]);
  for (size_t i = 0; i < len; ++i) {
    nfos_sdt_header_t *header =
        (nfos_sdt_header_t *)(uintptr_t)xsdt->entries[i];
    if (process_sdt(header, info)) {
      break;
    }
  }
}

static bool process_sdt(nfos_sdt_header_t *header, nfos_boot_info_t *info) {
  if (read_madt(header, info)) {
    return false;
  }
  if (read_srat(header, info)) {
    return false;
  }
  return false;
}

static bool read_madt(nfos_sdt_header_t *header, nfos_boot_info_t *info) {
  if (memcmp(header->signature, "APIC", sizeof(header->signature)) != 0 ||
      nfos_acpi_checksum(header, header->length) != 0) {
    return false;
  }
  nfos_madt_header_t *madt = (nfos_madt_header_t *)header;

  nfos_structure_header_t *ic = (nfos_structure_header_t *)(madt + 1);
  size_t ic_len = madt->header.length - sizeof(*madt);
  nfos_structure_header_t *ic_end = PTR_ADVANCE_BYTES(ic, ic_len);
  for (; ic < ic_end; ic = PTR_ADVANCE_BYTES(ic, ic->length)) {
    if (ic->type == NFOS_ACPI_IC_PROCESSOR_APIC) {
      nfos_madt_apic_t *cpu = (nfos_madt_apic_t *)ic;
      if (cpu->flags != 1) {
        continue;
      }

      info->cpus[info->num_cpus].apic_id = (uint32_t)cpu->apic_id;
      ++info->num_cpus;
      if (info->num_cpus >= MAX_CPUS) {
        break;
      }
    }
  }

  return true;
}

static bool read_srat(nfos_sdt_header_t *header, nfos_boot_info_t *info) {
  if (memcmp(header->signature, "SRAT", sizeof(header->signature)) != 0 ||
      nfos_acpi_checksum(header, header->length) != 0) {
    return false;
  }

  nfos_srat_header_t *srat = (nfos_srat_header_t *)header;

  nfos_structure_header_t *affinity = (nfos_structure_header_t *)(srat + 1);
  size_t affinity_len = srat->header.length - sizeof(*srat);
  nfos_structure_header_t *affinity_end =
      PTR_ADVANCE_BYTES(affinity, affinity_len);
  for (; affinity < affinity_end;
       affinity = PTR_ADVANCE_BYTES(affinity, affinity->length)) {
    if (affinity->type != NFOS_SRAT_APIC) {
      continue;
    }

    nfos_srat_apic_t *apic = (nfos_srat_apic_t *)affinity;
    if (apic->flags != 1) {
      continue;
    }

    uint32_t node_id = get_node_id(apic);
    size_t i = 0;
    for (; i < info->num_nodes; ++i) {
      if (info->nodes[i].id == node_id) {
        break;
      }
    }

    nfos_node_info_t *node = &info->nodes[i];
    // found a new node
    if (i == info->num_nodes) {
      if (info->num_nodes >= MAX_NODES) {
        break;
      }

      ++info->num_nodes;
      node->id = node_id;
    }

    if (node->num_cpus >= MAX_CPUS) {
      break;
    }

    node->cpus[node->num_cpus] = apic->apic_id;
    ++node->num_cpus;
  }

  return true;
}

static uint32_t get_node_id(nfos_srat_apic_t *apic) {
  uint32_t node = *(uint32_t *)apic->proximity_domain_high;
  node <<= 3;
  node |= (uint32_t)apic->proximity_domain_low;
  return node;
}
