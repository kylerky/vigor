#ifndef _STAT_KEY_H_INCLUDED_
#define _STAT_KEY_H_INCLUDED_

#include <stdint.h>
#include "libvig/stubs/ether_addr.h"

struct StaticKey {
  struct ether_addr addr;
  uint16_t device;
};

#endif//_STAT_KEY_H_INCLUDED_