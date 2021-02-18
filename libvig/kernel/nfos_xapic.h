#ifndef NFOS_XAPIC_H
#define NFOS_XAPIC_H

#include <stdint.h>

#define NFOS_XAPIC_BASE_ADDRESS 0xfee00000UL
#define NFOS_XAPIC_ICR_DEST_OFFSET 24

static const unsigned NFOS_XAPIC_LEVEL = 14;
static const unsigned NFOS_XAPIC_DELIVERY = 8;
static const unsigned NFOS_XAPIC_TRIGGER = 15;
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

static inline void nfos_apic_send_sipi(uint8_t dest, uint8_t vector) {
  nfos_apic_write(NFOS_APIC_ICR_HIGHER, dest << NFOS_XAPIC_ICR_DEST_OFFSET);
  nfos_apic_write(NFOS_APIC_ICR_LOWER,
                  (NFOS_IPI_STARTUP << NFOS_XAPIC_DELIVERY) | vector);
}

static inline void nfos_apic_send_init(uint8_t dest) {
  nfos_apic_write(NFOS_APIC_ICR_HIGHER, dest << NFOS_XAPIC_ICR_DEST_OFFSET);
  nfos_apic_write(NFOS_APIC_ICR_LOWER,
                  (1 << NFOS_XAPIC_TRIGGER) | (1 << NFOS_XAPIC_LEVEL) |
                      (NFOS_IPI_INIT << NFOS_XAPIC_DELIVERY));

  nfos_apic_write(NFOS_APIC_ICR_HIGHER, dest << NFOS_XAPIC_ICR_DEST_OFFSET);
  nfos_apic_write(NFOS_APIC_ICR_LOWER,
                  (1 << NFOS_XAPIC_TRIGGER) | (0 << NFOS_XAPIC_LEVEL) |
                      (NFOS_IPI_INIT << NFOS_XAPIC_DELIVERY));
}

#endif // NFOS_XAPIC_H
