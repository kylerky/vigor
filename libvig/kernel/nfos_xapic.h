#ifndef NFOS_XAPIC_H
#define NFOS_XAPIC_H

#include <stdint.h>
#include "nfos_utils.h"

static const unsigned NFOS_XAPIC_LEVEL = 14;
static const unsigned NFOS_XAPIC_DELIVERY = 8;
static const unsigned NFOS_XAPIC_TRIGGER = 15;
typedef enum nfos_xapic_register {
  NFOS_X2APIC_ICR = 0x830,
} nfos_xapic_register_t;

typedef enum nfos_ipi_mode {
  NFOS_IPI_INIT = 0b101,
  NFOS_IPI_STARTUP = 0b110,
} nfos_ipi_mode_t;

static inline void nfos_apic_write(const nfos_xapic_register_t reg,
                                   const uint32_t high, const uint32_t low) {
  x86_wrmsr((uint32_t)reg, high, low);
}

static inline void nfos_apic_send_sipi(const uint32_t dest,
                                       const uint8_t vector) {
  nfos_apic_write(NFOS_X2APIC_ICR, dest,
                  (NFOS_IPI_STARTUP << NFOS_XAPIC_DELIVERY) | vector);
}

static inline void nfos_apic_send_init(const uint32_t dest) {
  nfos_apic_write(NFOS_X2APIC_ICR, dest,
                  (1 << NFOS_XAPIC_TRIGGER) | (1 << NFOS_XAPIC_LEVEL) |
                      (NFOS_IPI_INIT << NFOS_XAPIC_DELIVERY));

  nfos_apic_write(NFOS_X2APIC_ICR, dest,
                  (1 << NFOS_XAPIC_TRIGGER) | (0 << NFOS_XAPIC_LEVEL) |
                      (NFOS_IPI_INIT << NFOS_XAPIC_DELIVERY));
}

#endif // NFOS_XAPIC_H
