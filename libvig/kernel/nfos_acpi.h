#ifndef NFOS_ACPI_H
#define NFOS_ACPI_H

#include <stdint.h>
#include <stddef.h>

#include "nfos_boot_info.h"
#include "nfos_utils.h"

#define ACPI_RSDP_SIGNATURE_LENGTH 8
#define ACPI_RSDP_OEM_ID_LENGTH 6
#define ACPI_RSDP_RESERVED_LENGTH 3

#define ACPI_SDT_SIGNATURE_LENGTH 4
#define ACPI_SDT_IGNORED_LENGTH 28

#define ACPI_SRAT_HEADER_RESERVED_LENGTH 12

typedef struct nfos_rsdp_v1 {
  char signature[ACPI_RSDP_SIGNATURE_LENGTH];
  uint8_t checksum;
  char oem_id[ACPI_RSDP_OEM_ID_LENGTH];
  uint8_t revision;
  uint32_t rsdt_address;
} PACKED nfos_rsdp_v1_t;

// fields available from ACPI 2.0
typedef struct nfos_rsdp_v2_extension {
  uint32_t length;
  uint64_t xsdt_address;
  uint8_t extended_checksum;
  uint8_t reserved[ACPI_RSDP_RESERVED_LENGTH];
} PACKED nfos_rsdp_v2_extension_t;

typedef struct nfos_rsdp_v2 {
  nfos_rsdp_v1_t first;
  nfos_rsdp_v2_extension_t second;
} PACKED nfos_rsdp_v2_t;

typedef struct nfos_sdt_header {
  char signature[ACPI_SDT_SIGNATURE_LENGTH];
  uint32_t length;
  uint8_t ignored[ACPI_SDT_IGNORED_LENGTH];
} PACKED nfos_sdt_header_t;

typedef struct nfos_rsdt {
  nfos_sdt_header_t header;
  uint32_t entries[];
} PACKED nfos_rsdt_t;

typedef struct nfos_xsdt {
  nfos_sdt_header_t header;
  uint64_t entries[];
} PACKED nfos_xsdt_t;

typedef struct nfos_madt_header {
  nfos_sdt_header_t header;
  uint32_t local_ic_addr;
  uint32_t flags;
} PACKED nfos_madt_header_t;

typedef struct nfos_structure_header {
  uint8_t type;
  uint8_t length;
} PACKED nfos_structure_header_t;

typedef struct nfos_madt_apic {
  nfos_structure_header_t header;
  uint8_t uid;
  uint8_t apic_id;
  uint32_t flags;
} PACKED nfos_madt_apic_t;

typedef struct nfos_srat_header {
  nfos_sdt_header_t header;
  uint8_t reserved[ACPI_SRAT_HEADER_RESERVED_LENGTH];
} PACKED nfos_srat_header_t;

typedef struct nfos_srat_apic {
  nfos_structure_header_t header;
  uint8_t proximity_domain_low;
  uint8_t apic_id;
  uint32_t flags;
  uint8_t local_sapic_eid;
  uint8_t proximity_domain_high[3];
  uint32_t clock_domain;
} PACKED nfos_srat_apic_t;

uint8_t nfos_acpi_checksum(void *ptr, size_t len);
#define NFOS_ACPI_CHECKSUM_STRUCT(s) nfos_acpi_checksum((s), sizeof(*(s)))

void nfos_acpi_parse_rsdp(void *p, nfos_boot_info_t *info);

enum nfos_acpi_ic_type {
  NFOS_ACPI_IC_PROCESSOR_APIC = 0,
};

enum nfos_srat_affinity_type {
  NFOS_SRAT_APIC = 0,
};

#endif // NFOS_ACPI_H
