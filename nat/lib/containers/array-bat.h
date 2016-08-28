#ifndef _ARRAY_BAT_H_INCLUDED_
#define _ARRAY_BAT_H_INCLUDED_

#include "lib/static-component-params.h"
#include "lib/containers/batcher.h"

#define ARRAY_BAT_EL_TYPE struct Batcher
#define ARRAY_BAT_CAPACITY RTE_MAX_ETHPORTS
#define ARRAY_BAT_EL_INIT batcher_init


#ifdef KLEE_VERIFICATION
struct ArrayBat
{
  char dummy;
};
#else//KLEE_VERIFICATION
struct ArrayBat
{
  struct Batcher data[ARRAY_BAT_CAPACITY];
};
#endif//KLEE_VERIFICATION

/*@
  //params: list<struct rte_mbuf*> , batcherp
  predicate arrp_bat(list<list<struct rte_mbuf*> > data, struct ArrayBat *arr);
  predicate arrp_bat_acc(list<list<struct rte_mbuf*> > data, struct ArrayBat *arr,
                         int idx, ARRAY_BAT_EL_TYPE *el);

  fixpoint ARRAY_BAT_EL_TYPE *arrp_the_missing_cell_bat(struct ArrayBat *arr,
                                                        int idx);
  @*/


#endif//_ARRAY_BAT_H_INCLUDED_
