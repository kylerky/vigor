global ap_init_start
global ap_init_end

extern nfos_ap_index
extern nfos_ap_main
extern nfos_halt

section .text
; APs initially in real mode
BITS 16
ap_init_start:
    ; According to MultiProcessor Specification v1.4 B.4.2 USING STARTUP IPI,
    ; a Startup IPI set CS:IP to VV00:0000h where VV is the least significant
    ; byte of the vector in the IPI. Since ap_init_start is at VV00:0000h, CS:0
    ; points ap_init_start.
    ;
    ; By loading the value of cs into ds, we can address data using relative
    ; addresses with respect to ap_init_start.
    ;
    ; The following two instructions load the value of cs into ds.
    mov ax, cs
    mov ds, ax

    ; The following instruction loads the GDT register with the descriptor of
    ; the GDT at ap_gdt_32 using a relative address.
    lgdt [ap_gdt_32.descriptor - ap_init_start]

    ; The following instruction sets CR0.PE to 1. It enables protected mode of
    ; the processor.
    mov eax, cr0
    or eax, 1
    mov cr0, eax

    ; At this moment, the processor is already in protected mode. However, its
    ; CS register is not yet loaded with the right code segment. Also, the
    ; default operand size of this section is 16 bits so we need dword to
    ; instruct the assembler to treat ap_protected as a 32-bit address.
    ; This long jump is essential in refreshing the CS register and serialising
    ; the processor's instructions according to section 9.9.1 - Switching to
    ; Protected Mode of the CPU manual.

    ;
    ; The long jump loads the CS register with the third segment in ap_gdt_32
    ; and direct the control flow to ap_protected. The segment is a code segment
    ; with a base of 0 and a limit of 0xffffffff.
    jmp dword (1 << 3):ap_protected

ap_gdt_32:
    ; The first descriptor is never used so it can be 0
    dq 0
    ; Base (bit 56-63) (0): bits 24-31 of the base address
    ; Granularity (bit 55): determines the scaling (4k when set) of the segment limit field
    ; D/B (bit 54): should be set for 32-bit code segment
    ; L (bit 53): indicates a 64-bit code segment
    ; AVL (bit 52): available for the system
    ; Limit (bit 48-51) (0xf): bits 16-19 of the limit
    ; Present (bit 47): indicates whether the segment is present in memory
    ; Descriptor privilege level (bit 45-46) (0): specifies the privilege level of the segment
    ; S (bit 44): set to indicate this is a code or data segment
    ; Type (bit 40-43) (0xb): indicates that this is a rx code segment (with accessed bit set)
    ; Base (bit 16-39) (0): bits 0-23 of the base address
    ; Limit (bit 0-15) (0xffff): bits 0-15 of the limit
    dq (1<<55) | (1<<54) | (0xf<<48) | (1<<47) | (1<<44) | (0xb<<40) | (0xffff)
    ; Base (bit 56-63) (0): bits 24-31 of the base address
    ; Granularity (bit 55): determines the scaling (4k when set) of the segment limit field
    ; D/B (bit 54): should be set for 32-bit code segment
    ; L (bit 53): indicates a 64-bit code segment
    ; AVL (bit 52): available for the system
    ; Limit (bit 48-51) (0xf): bits 16-19 of the limit
    ; Present (bit 47): indicates whether the segment is present in memory
    ; Descriptor privilege level (bit 45-46) (0): specifies the privilege level of the segment
    ; S (bit 44): set to indicate this is a code or data segment
    ; Type (bit 40-43) (0x3): indicates that this is a rw data segment (with accessed bit set)
    ; Base (bit 16-39) (0): bits 0-23 of the base address
    ; Limit (bit 0-15) (0xffff): bits 0-15 of the limit
    dq (1<<55) | (1<<54) | (0xf<<48) | (1<<47) | (1<<44) | (0x3<<40) | (0xffff)

.descriptor:
    ; GDT descriptor
    dw $ - ap_gdt_32 - 1
    dd ap_gdt_32

ap_init_end:

BITS 32
ap_protected:
    ; The following 3 instructions load the DS and SS registers with the second
    ; segment in ap_gdt_32, which is a data segment with a base of 0 and a limit
    ; of 0xffffffff
    mov ax, (2 << 3)
    mov ds, ax
    mov ss, ax

    ; The following instruction calculate the address of the dedicated stack
    ; space for this application processor. Each APs has 1MiB of dedicated
    ; stacks space. APs take the stack space from the top of the allocated
    ; slots, one after the other according to nfos_ap_index. The APs will
    ; increment nfos_ap_index once they enter nfos_ap_main. The BSP will not
    ; start new APs until the AP increment nfos_ap_index so there will be no
    ; race condition.
    mov eax, nfos_ap_index
    shl eax, 20
    lea esp, [eax + stack_top]

    ; The function checks that the CPU has the features that we need.
    ;
    ; It will push a 32-bit address to the stack, which now has 1MiB of space
    ; available. Therefore, calling this function is safe.
    call start.check_cpu_features

    ; Because execution has reached this point, we know that the CPU supports all the
    ; features that we require.
    ; According to section 9.8.5 - Initializing IA-32e Mode of the CPU manual
    ; we need to follow these steps in order to switch to 64-bit mode.
    ;
    ; 1 - Starting from protected mode, disable paging. Because we assume that
    ;   we are already in protected mode and that paging is disabled, this step
    ;   is not needed.
    ;
    ; 2 - Enable physical-address extensions (PAE) by setting bit 5 in register CR4.
    ;   Reading and writing this register is only possible at privilege level (CPL)
    ;   0, which we assume.
    ;
    ; Bitwise ORing a register with a bit mask will set all the bits in that mask.
    ; All other bits are unchanged.
    mov eax, cr4
    or eax, 1 << 5
    mov cr4, eax

    ; This function puts the processor in IA32e mode. When the function returns,
    ; the processors will operate in compatibility mode.
    ;
    ; It will push a 32-bit address to the stack, which now has 1MiB of space
    ; available. Therefore, calling this function is safe.
    call start.enter_ia32e
    ; Because the CPU caches segment descriptors in private registers, it is not
    ; enough to load a new GDT. NFOS must also explicitly load the new CS
    ; descriptor by setting the CS register. Unlike other segment registers, CS
    ; cannot be loaded with the MOV instruction, but only with the JMP, CALL and
    ; RET instructions. Because we want the JMP instruction to set both the
    ; instruction pointer and code segment, we need to use a far jump instruction.
    jmp gdt64.code_segment:.ap_long

BITS 64
.ap_long:
    ; The CPU caches data segment selectors, just like the code segment selector.
    ; The 32-bit data segment selectors are still loaded and we should replace
    ; them. Segment descriptor 0 (the null segment) is invalid in 32-bit
    ; mode and causes an exception when used, but it is valid in 64-bit mode.
    ; In order to enable it, NFOS has to write 0 to each data segment register.
    xor ax, ax
    mov ss, ax
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax

    ; According to section 3.4.1 - General-Purpose Registers of the CPU manual
    ; the upper 32 bits of rsp are undefined in 32-bit modes. Therefore, we will
    ; need to put the stack pointer to esp, which will be zero extended to the
    ; 64-bit value of rsp.
    mov eax, nfos_ap_index
    shl eax, 20
    lea esp, [eax + stack_top]

    ; This function enables the features that we need before calling main.
    ;
    ; It will push a 64-bit address to the stack, which now has 1MiB of space
    ; available. Therefore, calling this function is safe.
    call start.before_main

    ; NFOS needs to guarantee that the stack pointer is aligned on a 16-byte
    ; boundary before nfos_ap_main() is invoked. We instruct the assembler to
    ; align stack_bottom to a 16-byte boundary.
    mov eax, nfos_ap_index
    shl eax, 20
    lea esp, [eax + stack_top]

    ; At this point all the preconditions have been satisfied and NFOS can invoke
    ; the C nfos_ap_main function
    call nfos_ap_main
    ; nfos_ap_main() never returns, therefore this code is unreachable.
    jmp nfos_halt
