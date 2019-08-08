# Skeleton Makefile for Vigor NFs
# Variables that should be defined by inheriting Makefiles:
# - NF_DEVICES := <number of devices during verif-time, default 2>
# - NF_FILES := <NF files for both runtime and verif-time, automatically includes state and autogenerated files, and shared NF files>
# - NF_AUTOGEN_SRCS := <NF files that are inputs to auto-generation>
# - NF_ARGS := <arguments to pass to the NF>
# - NF_LAYER := <network stack layer at which the NF operates, default 2>
# - NF_BENCH_NEEDS_REVERSE_TRAFFIC := <whether the NF needs reverse traffic for meaningful benchmarks, default false>
# Variables that can be passed when running:
# - NF_DPDK_ARGS - will be passed as DPDK part of the arguments
# -----------------------------------------------------------------------


# get current dir, see https://stackoverflow.com/a/8080530
SELF_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))

# Default value for arguments
NF_DEVICES ?= 2
NF_ARGS := --no-shconf $(NF_DPDK_ARGS) -- $(NF_ARGS)
NF_LAYER ?= 2
NF_BENCH_NEEDS_REVERSE_TRAFFIC ?= false

# If KLEE paths are not defined (eg because the user installed deps themselves), try to compute it based on KLEE_INCLUDE.
KLEE_BUILD_PATH ?= $(KLEE_INCLUDE)/../build

# DPDK stuff
include $(RTE_SDK)/mk/rte.vars.mk

# Same name for everyone, makes it easier to run them all with the same script
APP := nf
# allow the use of advanced globs in paths
SHELL := /bin/bash -O extglob -O globstar -c
# NF base source; somehow because of DPDK makefile magic wildcards mess up everything here, so we ask echo to expand those
SRCS-y := $(shell echo $(SELF_DIR)/nf_main.c \
                       $(SELF_DIR)/libvig/*.c \
                       $(SELF_DIR)/libvig/containers/*.c)
SRCS-y += $(NF_FILES)
# Compiler flags
CFLAGS += -I $(SELF_DIR)
CFLAGS += -std=gnu99
CFLAGS += -DCAPACITY_POW2
CFLAGS += -O3
#CFLAGS += -O0 -g -rdynamic -DENABLE_LOG -Wfatal-errors

# DPDK stuff, unless we're benchmarking (see remarks on the benchmark target)
ifeq (,$(findstring benchmark-,$(MAKECMDGOALS)))
include $(RTE_SDK)/mk/rte.extapp.mk
endif

# ========
# Default: build the nf Linux executable
# ========
.DEFAULT_GOAL := executable
executable: autogen build/app/nf


# ========
# VeriFast
# ========

LIBVIG_SRC_ARITH := $(SELF_DIR)/libvig/containers/arith.c \
                    $(SELF_DIR)/libvig/containers/modulo.c
LIBVIG_SRC_Z3 := $(subst .c,.o,$(LIBVIG_SRC_ARITH)) \
                 $(SELF_DIR)/libvig/containers/bitopsutils.c \
                 $(SELF_DIR)/libvig/containers/mod_pow2.c \
                 $(SELF_DIR)/libvig/containers/lpm-dir-24-8-lemmas.c \
                 $(SELF_DIR)/libvig/containers/lpm-dir-24-8.c
LIBVIG_SRC := $(subst .c,.o,$(LIBVIG_SRC_Z3)) \
              $(SELF_DIR)/libvig/containers/double-chain-impl.c \
              $(SELF_DIR)/libvig/containers/double-chain.c \
              $(SELF_DIR)/libvig/containers/map-impl.c \
              $(SELF_DIR)/libvig/containers/map-impl-pow2.c \
              $(SELF_DIR)/libvig/containers/double-map.c \
              $(SELF_DIR)/libvig/containers/vector.c \
              $(SELF_DIR)/libvig/containers/prime.c \
              $(SELF_DIR)/libvig/containers/listutils-lemmas.c \
              $(SELF_DIR)/libvig/containers/transpose-lemmas.c \
              $(SELF_DIR)/libvig/containers/permutations.c \
              $(SELF_DIR)/libvig/containers/cht.c \
              $(SELF_DIR)/libvig/packet-io.c \
              $(SELF_DIR)/libvig/containers/map.c \
              $(SELF_DIR)/libvig/coherence.c \
              $(SELF_DIR)/libvig/expirator.c

VERIFAST_COMMAND := verifast -I $(SELF_DIR) -I $(SELF_DIR)/libvig/stubs/dpdk -allow_assume -shared
VERIFAST_CLEAN_COMMAND := rm -rf $(SELF_DIR)/**/*.vfmanifest
verifast:
	@printf '\n\n!!!\n\n'
	@printf 'This is gonna take a while, go make a nice cup of tea...\n\n'
	@printf 'Note that we are verifying the code twice, once with the power-of-two optimization for the map and once without\n'
	@printf 'Also, some parts of the proof can only be verified with Z3 and some with the standard VeriFast solver, so we split the verification in parts...\n'
	@printf '\n!!!\n\n'
	@$(VERIFAST_CLEAN_COMMAND)
	@$(VERIFAST_COMMAND) -emit_vfmanifest $(LIBVIG_SRC_ARITH)
	@$(VERIFAST_COMMAND) -prover="Z3v4.5" -emit_vfmanifest $(LIBVIG_SRC_Z3)
	@$(VERIFAST_COMMAND) -emit_vfmanifest $(LIBVIG_SRC)
	@$(VERIFAST_COMMAND) -emit_vfmanifest -D CAPACITY_POW2 $(LIBVIG_SRC)



# =========================================
# Verification general commands and targets
# =========================================

# Cleanup
CLEAN_COMMAND := rm -rf build *.bc *.os *.ll {loop,state}.{c,h} $(SELF_DIR)/**/*.gen.{c,h}
# Compilation
COMPILE_COMMAND := clang
# Linking with klee-uclibc, but without some methods we are stubbing (not sure why they're in klee-uclibc.bca); also purge the pointless GNU linker warnings so KLEE doesn't warn about module asm
LINK_COMMAND := llvm-ar x $(KLEE_BUILD_PATH)/Release+Debug+Asserts/lib/klee-uclibc.bca && \
                rm -f sleep.os vfprintf.os socket.os exit.os fflush_unlocked.os fflush.os && \
                llvm-link -o nf_raw.bc  *.os *.bc && \
                llvm-dis -o nf_raw.ll nf_raw.bc && \
                sed -i -e 's/module asm ".section .gnu.warning.*"//g' -e 's/module asm "\\09.previous"//g' -e 's/module asm ""//g' nf_raw.ll && \
                llvm-as -o nf_raw.bc nf_raw.ll
# Optimization; analyze and remove as much provably dead code as possible (exceptions are stubs; also, mem* functions, not sure why it DCEs them since they are used...maybe related to LLVM having intrinsics for them?)
# We tried adding '-constprop -ipconstprop -ipsccp -correlated-propagation -loop-deletion -dce -die -dse -adce -deadargelim -instsimplify'; this works but the traced prefixes seem messed up :(
OPT_EXCEPTIONS := memset,memcpy,memmove,stub_abort,stub_free,stub_hardware_read,stub_hardware_write,stub_prefetch,stub_rdtsc,stub_socket,stub_strerror,stub_delay
OPT_COMMAND := opt -basicaa -basiccg -internalize -internalize-public-api-list=main,$(OPT_EXCEPTIONS) -globaldce nf_raw.bc > nf.bc
# KLEE verification; if something takes longer than expected, try --max-solver-time=3 --debug-report-symbdex (to avoid symbolic indices)
VERIF_COMMAND := /usr/bin/time -v \
                 klee -no-externals -allocate-determ -allocate-determ-start-address=0x00040000000 -allocate-determ-size=1000 -dump-call-traces -dump-call-trace-prefixes -solver-backend=z3 -exit-on-error -max-memory=750000 -search=dfs -condone-undeclared-havocs --debug-report-symbdex \
                 nf.bc

# Cleanup after ourselves, but don't shadow the existing DPDK target
clean-vigor:
	@$(CLEAN_COMMAND)
clean: clean-vigor

# Built-in DPDK default target, make it aware of autogen, and make it clean every time because our dependency tracking is nonexistent...
all: clean autogen



# =======================
# Symbex with DPDK models
# =======================

# Basic flags: only compile, emit debug code, in LLVM format, with checks for overflows
#              (but not unsigned overflows - they're not UB and DPDK depends on them)
#              also no unused-value, DPDK triggers that...
VERIF_FLAGS := -c -g -emit-llvm -fsanitize=signed-integer-overflow -Wno-unused-value
# Basic includes: NF root, KLEE, DPDK cmdline
VERIF_INCLUDES := -I $(SELF_DIR) -I $(KLEE_INCLUDE) -I $(RTE_SDK)/lib/librte_cmdline
# Basic defines
VERIF_DEFS := -D_GNU_SOURCE -DKLEE_VERIFICATION
# Number of devices
VERIF_DEFS += -DSTUB_DEVICES_COUNT=$(NF_DEVICES)
# NF base
VERIF_FILES := $(SELF_DIR)/nf_main.c $(SELF_DIR)/libvig/nf_util.c
# Specific NF
VERIF_FILES += $(NF_FILES) loop.c
# Stubs
VERIF_FILES += $(SELF_DIR)/libvig/stubs/**/*_stub.c $(SELF_DIR)/libvig/stubs/externals/*.c
# DPDK cmdline parsing library, always included, we don't want/need to stub it... and the string function it uses
VERIF_FILES += $(RTE_SDK)/lib/librte_cmdline/*.c $(RTE_SDK)/lib/librte_eal/common/eal_common_string_fns.c

# The only thing we don't put in variables is the DPDK stub headers, since we don't want to use those for the other symbex targets
symbex: clean autogen
	@$(COMPILE_COMMAND) $(VERIF_DEFS) $(VERIF_INCLUDES) -I $(SELF_DIR)/libvig/stubs/dpdk $(VERIF_FILES) $(VERIF_FLAGS)
	@$(LINK_COMMAND)
	@$(OPT_COMMAND)
	@$(VERIF_COMMAND) $(NF_ARGS)
	@$(CLEAN_COMMAND)



# ==================================
# Symbex with hardware and OS models
# ==================================

# CPUFLAGS is set to a sentinel value; usually it's passed from the DPDK build system
VERIF_WITHDPDK_DEFS := -DRTE_COMPILE_TIME_CPUFLAGS=424242
# Let hardware stubs know we want them
VERIF_WITHDPDK_DEFS += -DVIGOR_STUB_HARDWARE
# We need librte_eal/common because eal_private.h is in there, required by eal_thread.c...
# We need bus/pci because the linuxapp PCI stuff requires a private.h file in there...
# net/ixgbe is for stub hardware (the ixgbe driver)
VERIF_WITHDPDK_INCLUDES := -I $(RTE_SDK)/$(RTE_TARGET)/include \
			   -I $(RTE_SDK)/lib/librte_eal/common \
			   -I $(RTE_SDK)/drivers/bus/pci \
			   -I $(RTE_SDK)/drivers/net/ixgbe
# And then some special DPDK includes: builtin_stubs for built-ins DPDK uses, rte_config.h because many files forget to include it
VERIF_WITHDPDK_INCLUDES += --include=libvig/stubs/builtin_stub.h --include=rte_config.h
# Low-level stubs for specific functions
VERIF_WITHDPDK_FILES := $(SELF_DIR)/libvig/stubs/dpdk_low_level_stub.c
# Platform-independent and Linux-specific EAL
VERIF_WITHDPDK_FILES += $(RTE_SDK)/lib/librte_eal/common/*.c $(RTE_SDK)/lib/librte_eal/linuxapp/eal/*.c
# Default ring mempool driver
VERIF_WITHDPDK_FILES += $(RTE_SDK)/drivers/mempool/ring/rte_mempool_ring.c
# Other libraries, except acl and distributor which use CPU intrinsics (there is a generic version of distributor, but we don't need it),
# and power has been broken for a while: http://dpdk.org/ml/archives/dev/2016-February/033152.html
VERIF_WITHDPDK_FILES += $(RTE_SDK)/lib/!(librte_acl|librte_distributor|librte_power)/*.c
# PCI driver support (for ixgbe driver)
VERIF_WITHDPDK_FILES += $(RTE_SDK)/drivers/bus/pci/*.c $(RTE_SDK)/drivers/bus/pci/linux/*.c
# ixgbe driver
VERIF_WITHDPDK_FILES += $(RTE_SDK)/drivers/net/ixgbe/ixgbe_{fdir,flow,ethdev,ipsec,pf,rxtx,tm}.c $(RTE_SDK)/drivers/net/ixgbe/base/ixgbe_{api,common,phy,82599}.c
# Hardware stubs
VERIF_WITHDPDK_FILES += $(SELF_DIR)/libvig/stubs/hardware_stub.c

symbex-withdpdk: clean autogen
	@$(COMPILE_COMMAND) $(VERIF_DEFS) $(VERIF_WITHDPDK_DEFS) $(VERIF_INCLUDES) $(VERIF_WITHDPDK_INCLUDES) $(VERIF_FILES) $(VERIF_WITHDPDK_FILES) $(VERIF_FLAGS)
	@$(LINK_COMMAND)
	@$(OPT_COMMAND)
	@$(VERIF_COMMAND) $(NF_ARGS)
	@$(CLEAN_COMMAND)



# ====================================
# Symbex with hardware models and DSOS
# ====================================

# Convert the bash-style NF arguments (nf --no-shconf -- -n 3 -m 6) into
# C-style char*[] comma separated list
# of c-strings ("nf","--no-shconf","--","-n","3","-m","6") for DSOS to put
# into argv at compilation time.
dquote := \"
NF_ARGUMENTS_MACRO := -DNF_ARGUMENTS=\"$(subst $(space),$(dquote)$(comma)$(dquote),nf.bc $(NF_ARGS))\"
symbex-withdsos: clean autogen
	@$(COMPILE_COMMAND) $(VERIF_DEFS) $(VERIF_WITHDPDK_DEFS) $(NF_ARGUMENTS_MACRO) -DDSOS $(VERIF_INCLUDES) $(VERIF_WITHDPDK_INCLUDES) $(VERIF_FILES) $(VERIF_WITHDPDK_FILES) $(SELF_DIR)/libvig/kernel/*.c $(VERIF_FLAGS) -mssse3 -msse2 -msse4.1
	@$(LINK_COMMAND)
	@$(OPT_COMMAND)
	@$(VERIF_COMMAND) $(NF_ARGS)
	@$(CLEAN_COMMAND)



# ==========
# Validation
# ==========

validate: autogen
	@cd $(SELF_DIR)/validator && make $(notdir $(shell pwd))



# =======
# Running
# =======

run: all
	@sudo ./build/app/nf $(NF_ARGS) || true



# ============
# Benchmarking
# ============

# It seems the DPDK makefiles really don't like being recursively invoked - and benchmarking invokes make run; so we just don't include the DPDK makefile if we're benchmarking
benchmark-%:
	cd "$(SELF_DIR)/bench" && ./bench.sh "$(shell pwd)" $(subst benchmark-,,$@)
	mv ../bench/$@.results .
	printf '\n\nDone! Results are in $@.results, log file in $@.log\n\n'
# bench scripts use these to autodetect the NF type
_print-layer:
	@echo $(NF_LAYER)
_print-needsreverse:
	@echo $(NF_BENCH_NEEDS_REVERSE_TRAFFIC)

# ======================
# Counting lines of code
# ======================

# cloc instead of sloccount because the latter does not report comments, and all VeriFast annotations are comments

count-loc: autogen
	@cloc $(SRCS-y) $(AUTO_GEN_FILES)

count-fullstack-loc: autogen
	@cloc $(SRCS-y) $(AUTO_GEN_FILES) $(VERIF_WITHDPDK_FILES)

count-spec-loc:
	@cloc spec.py

count-lib-loc:
	@# Bit of a hack for this one, cloc can't be given a custom language but for some reason it knows about Pig Latin, which is never gonna happen in our codebase, so...
	@cloc --quiet --force-lang 'Pig Latin',gh  $(subst .o,.c,$(LIBVIG_SRC)) $(SELF_DIR)/libvig/containers/*.gh | sed 's/Pig Latin/VeriFast /g'
	@echo "NOTE: Annotations == VeriFast code + C comments - $$(grep '//[^@]' $(subst .o,.c,$(LIBVIG_SRC)) | wc -l) (that last number is the non-VeriFast C comments)"
	@if grep -F '/*' $(subst .o,.c,$(LIBVIG_SRC)) | grep -vF '/*@'; then echo 'ERROR: There are multiline non-VeriFast comments in the C code, the total above is wrong!'; fi



# =============
# Create new NF
# =============

new-nf:
	@read -p 'NF short name, e.g. "nat": ' name; \
	 mkdir vig$${name}; \
	 cp template/* vig$${name}/.; \
	 echo "Go to the vig$${name} folder, and check out the comments in each file."
