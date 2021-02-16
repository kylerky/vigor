#include <stdint.h>

#define NFOS_XAPIC_BASE_ADDRESS 0xfee00000UL
#define NFOS_XAPIC_ICR_DEST_OFFSET 24

typedef enum nfos_xapic_register {
  NFOS_APIC_ICR_LOWER = 0x300,
  NFOS_APIC_ICR_HIGHER = 0x310,
} nfos_xapic_register_t;

typedef enum nfos_ipi_mode {
  NFOS_IPI_INIT = 0b101,
  NFOS_IPI_STARTUP = 0b110,
} nfos_ipi_mode_t;

static inline void nfos_apic_write(nfos_xapic_register_t reg, uint32_t val) {
  *(volatile uint32_t *)(NFOS_XAPIC_BASE_ADDRESS + (uintptr_t)reg) = val;
}

static inline void nfos_apic_send_ipi(uint32_t dest, nfos_ipi_mode_t mode,
                                      uint8_t vector) {
  static const unsigned LEVEL = 14;
  static const unsigned MODE = 8;
  nfos_apic_write(NFOS_APIC_ICR_HIGHER, dest << NFOS_XAPIC_ICR_DEST_OFFSET);
  nfos_apic_write(NFOS_APIC_ICR_LOWER, (1 << LEVEL) | (mode << MODE) | vector);
}
