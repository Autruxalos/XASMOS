; =============================================================================
; XBOOT - Bootloader XASMOS  [XSPEC-0001]
; Load XKERNEL (bin/xkernel.bin) from sector 1 from drive to 0x0000:0x9000
; Uses INT 13h LBA extended (AH=42h), with fallback to CHS of 63 sectors.
; =============================================================================
[BITS 16]
[ORG 0x7C00]

xboot_main:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00

    mov [BOOT_DRIVE], dl

    mov ax, 0x0003
    int 0x10

    mov si, MSG_LOADING
    call bios_print

    ; Verificar soporte INT 13h extendido (LBA)
    mov bx, 0x55AA
    mov dl, [BOOT_DRIVE]
    int 0x13
    jc  .use_chs
    cmp bx, 0xAA55
    jne .use_chs

    mov si, MSG_LBA
    call bios_print

    ; IMPORTANTE: el DAP requiere OFFSET en +4 y SEGMENTO en +6.
    ; Como el stack crece hacia abajo, lo ultimo en pushearse queda
    ; en la direccion mas baja -> hay que pushear SEGMENTO antes que OFFSET.
    push dword 0             ; LBA alto
    push dword 1             ; LBA bajo = sector 1 (justo tras el MBR)
    push word  0x0000        ; segmento destino -> fisico 0x9000
    push word  0x9000        ; offset destino
    push word  64            ; sectores a leer (32 KB)
    push word  0x0010        ; tamano DAP

    mov si, sp
    mov ah, 0x42
    mov dl, [BOOT_DRIVE]
    int 0x13
    add sp, 16
    jc  .error

    mov si, MSG_DEBUG_LBA_OK
    call bios_print

    jmp .loaded

.use_chs:
    mov si, MSG_CHS
    call bios_print

    mov ax, 0x0000
    mov es, ax
    mov bx, 0x9000

    mov ah, 0x02
    mov al, 63
    mov ch, 0
    mov dh, 0
    mov cl, 2
    mov dl, [BOOT_DRIVE]
    int 0x13
    jc  .error

    add bx, 63 * 512
    mov ah, 0x02
    mov al, 63
    mov ch, 0
    mov dh, 1
    mov cl, 1
    mov dl, [BOOT_DRIVE]
    int 0x13

.loaded:
    mov si, MSG_OK
    call bios_print

   mov ah, 0x0E
   mov al, 'Y'
   mov bx, 0x0007
   int 0x10

    jmp 0x0000:0x9000

.error:
    mov si, MSG_ERROR
    call bios_print
    push ax
    mov  al, ah
    call print_hex_byte
    pop  ax
.halt:
    cli
    hlt
    jmp .halt

bios_print:
    mov ah, 0x0E
    mov bx, 0x0007
.loop:
    lodsb
    or  al, al
    jz  .done
    int 0x10
    jmp .loop
.done:
    ret

print_hex_byte:
    push ax
    push cx
    mov  cx, ax
    mov  al, cl
    shr  al, 4
    call .nibble
    mov  al, cl
    and  al, 0x0F
    call .nibble
    mov  ah, 0x0E
    mov  al, 0x0D
    int  0x10
    mov  al, 0x0A
    int  0x10
    pop  cx
    pop  ax
    ret
.nibble:
    cmp  al, 10
    jl   .digit
    add  al, 'A' - 10
    jmp  .print
.digit:
    add  al, '0'
.print:
    mov  ah, 0x0E
    mov  bx, 0x0007
    int  0x10
    ret

BOOT_DRIVE  db 0
MSG_LOADING db 'XASMOS Boot - Loading...', 13, 10, 0
MSG_LBA     db 'LBA Mode', 13, 10, 0
MSG_CHS     db 'CHS Mode', 13, 10, 0
MSG_OK      db 'Kernel loaded! skipping...', 13, 10, 0
MSG_ERROR   db 'ERROR reading disk! Code: ', 0
MSG_DEBUG_LBA_OK db 'K', 0

times 510 - ($ - $$) db 0
dw 0xAA55

