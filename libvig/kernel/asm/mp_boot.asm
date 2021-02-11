extern nfos_ap_index
extern nfos_ap_main
extern nfos_halt

section .text
; APs initially in real mode
BITS 16
ap_start:
    mov ax, cs
    mov ds, ax
    lgdt [ap_gdt_32.descriptor - ap_start]

    mov eax, cr0
    or eax, 1
    mov cr0, eax

    ; dword need to avoid truncation
    jmp dword (1 << 3):ap_protected

ap_gdt_32:
    ; The first descriptor is never used so it can be 0
    dq 0
    ; Base (bit 56-63) (0): bits 24-31 of the base address
    ; Granularity (bit 55): determines the scaling (4k when set) of the segment limit field
    ; D/B (bit 54): should be set for 32-bit code segement
    ; L (bit 53): indicates a 64-bit code segment
    ; AVL (bit 52): available for the system
    ; Limit (bit 48-51) (0xf): bits 16-19 of the limit
    ; Present (bit 47): indicates whether the segment is present in memory
    ; Descriptor privilege level (bit 45-46) (0): specifies the privilege level of the segment
    ; S (bit 44): set to indicate this is a code or data segment
    ; Type (bit 40-43) (0xb): indicates that this is a rx code segment (with accessed bit set)
    ; Base (bit 16-39) (0): bits 0-23 of the base address
    ; Limit (bit 0-15) (0xf): bits 0-15 of the limit
    dq (1<<55) | (1<<54) | (0xf<<48) | (1<<47) | (1<<44) | (0xb<<40) | (0xf)
    ; Base (bit 56-63) (0): bits 24-31 of the base address
    ; Granularity (bit 55): determines the scaling (4k when set) of the segment limit field
    ; D/B (bit 54): should be set for 32-bit code segement
    ; L (bit 53): indicates a 64-bit code segment
    ; AVL (bit 52): available for the system
    ; Limit (bit 48-51) (0xf): bits 16-19 of the limit
    ; Present (bit 47): indicates whether the segment is present in memory
    ; Descriptor privilege level (bit 45-46) (0): specifies the privilege level of the segment
    ; S (bit 44): set to indicate this is a code or data segment
    ; Type (bit 40-43) (0x3): indicates that this is a rw data segment (with accessed bit set)
    ; Base (bit 16-39) (0): bits 0-23 of the base address
    ; Limit (bit 0-15) (0xf): bits 0-15 of the limit
    dq (1<<55) | (1<<54) | (0xf<<48) | (1<<47) | (1<<44) | (0x3<<40) | (0xf)

.descriptor:
    ; GDT descriptor
    dw $ - ap_gdt_32 - 1
    dd ap_gdt_32

ap_end:

BITS 32
ap_protected:
    mov ax, (2 << 3)
    mov ds, ax
    mov ss, ax

    mov eax, ap_index
    shl eax, 20
    lea esp, [eax + stack_top]

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

    call start.enter_ia32e
    jmp gdt64.code_segment:.64_bit

BITS 64
.64_bit
    ; The CPU caches data segment selectors, just like the code segment selector.
    ; The 32-bit data segment selectors are still loaded and we shoud replace
    ; them. Segment descriptor 0 (the null segment) is invalid in 32-bit
    ; mode and causes an exception when used, but it is valid in 64-bit mode.
    ; In order to enable it, NFOS has to write 0 to each data segment register.
    xor ax, ax
    mov ss, ax
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax

    mov eax, ap_index
    shl eax, 20
    lea esp, [eax + stack_top]

    call start.before_main

    mov eax, ap_index
    shl eax, 20
    lea esp, [eax + stack_top]

    call ap_main
    ; ap_main() never returns, therefore this code is unreachable.
    jmp nfos_halt
