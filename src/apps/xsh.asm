; =============================================================================
; XSH — Shell 16-bit nativa de XOS
; Compatible 8086 / 286 / 386+ / x86_64 (corre en Real Mode)
; =============================================================================
[BITS 16]

; --- Variables ---
xsh_cwd_name:   db '|', 0
                times 31 db 0
xsh_is_sprusr:  db 0          ; 0 = usuario, 1 = sprusr
xsh_linebuf:    times 80 db 0
xsh_argc:       db 0

; --- Prompt ---
msg_prompt_user: db ' &>> ', 0
msg_prompt_root: db ' (>> ', 0
msg_unknown:     db 'XSH: comando no reconocido', 13, 10, 0
msg_ver:         db 'XSH v0.2 — 16-bit compatible', 13, 10, 0
msg_sprusr:      db 'Modo sprusr activado', 13, 10, 0
msg_halt:        db 13, 10, 'XOS detenido.', 13, 10, 0

; =============================================================================
; Punto de entrada
; =============================================================================
global xsh_main
xsh_main:
    mov byte [xsh_cwd_name], '|'
    mov byte [xsh_cwd_name+1], 0
    mov byte [xsh_is_sprusr], 0

.loop:
    ; Prompt
    cmp byte [xsh_is_sprusr], 1
    je  .root_prompt
    mov si, msg_prompt_user
    jmp .show
.root_prompt:
    mov si, msg_prompt_root
.show:
    call print16

    ; Leer línea (teclado BIOS)
    call xsh_read_line

    ; Si está vacía, volver
    cmp byte [xsh_linebuf], 0
    je  .loop

    ; Despachar comando
    call xsh_dispatch
    jmp .loop

; =============================================================================
; Lectura de línea con BIOS (INT 0x16)
; =============================================================================
xsh_read_line:
    push ax
    push bx
    push si
    mov  si, xsh_linebuf
    xor  bx, bx                 ; contador de caracteres

.read:
    xor  ah, ah
    int  0x16                   ; AL = ASCII, AH = scancode

    cmp  al, 13                 ; Enter
    je   .done
    cmp  al, 8                  ; Backspace
    je   .backspace
    cmp  al, 27                 ; ESC → limpiar
    je   .clear

    ; Límite de 79 caracteres
    cmp  bx, 79
    jge  .read

    mov  [si], al
    inc  si
    inc  bx

    ; Eco en pantalla
    mov  ah, 0x0E
    mov  bh, 0
    int  0x10
    jmp  .read

.backspace:
    test bx, bx
    jz   .read
    dec  si
    dec  bx
    mov  byte [si], 0
    ; Borrar en pantalla
    mov  ah, 0x0E
    mov  al, 8
    int  0x10
    mov  al, ' '
    int  0x10
    mov  al, 8
    int  0x10
    jmp  .read

.clear:
    mov  byte [xsh_linebuf], 0
    jmp  .done

.done:
    mov  byte [si], 0
    ; Nueva línea
    mov  ah, 0x0E
    mov  al, 13
    int  0x10
    mov  al, 10
    int  0x10
    pop  si
    pop  bx
    pop  ax
    ret

; =============================================================================
; Dispatcher simple (comparación de strings 16-bit)
; =============================================================================
xsh_dispatch:
    mov  si, xsh_linebuf

    ; ver
    mov  di, cmd_ver
    call strcmp16
    jc   .do_ver

    ; clear
    mov  di, cmd_clear
    call strcmp16
    jc   .do_clear

    ; list
    mov  di, cmd_list
    call strcmp16
    jc   .do_list

    ; make-dir
    mov  di, cmd_make_dir
    call strcmp16
    jc   .do_make_dir

    ; exofetch
    mov  di, cmd_exofetch
    call strcmp16
    jc   .do_exofetch

    ; sprusr
    mov  di, cmd_sprusr
    call strcmp16
    jc   .do_sprusr

    ; halt
    mov  di, cmd_halt
    call strcmp16
    jc   .do_halt

    ; Desconocido
    mov  si, msg_unknown
    call print16
    ret

.do_ver:
    mov  si, msg_ver
    call print16
    ret

.do_clear:
    mov  ax, 0x0003
    int  0x10
    ret

.do_list:
    ; Aquí llamarías a exfs_list_dir (versión 16-bit)
    ret

.do_make_dir:
    ; Aquí llamarías a exfs_make_obj (versión 16-bit)
    ret

.do_exofetch:
    call exofetch_main_16
    ret

.do_sprusr:
    mov  byte [xsh_is_sprusr], 1
    mov  si, msg_sprusr
    call print16
    ret

.do_halt:
    mov  si, msg_halt
    call print16
    cli
    hlt
    jmp  $

; =============================================================================
; Utilidades 16-bit
; =============================================================================
print16:
    mov  ah, 0x0E
    mov  bh, 0
.lp:
    lodsb
    or   al, al
    jz   .done
    int  0x10
    jmp  .lp
.done:
    ret

; Compara SI con DI. Carry = 1 si son iguales
strcmp16:
    push ax
    push si
    push di
.lp:
    mov  al, [si]
    mov  ah, [di]
    cmp  al, ah
    jne  .no
    test al, al
    jz   .yes
    inc  si
    inc  di
    jmp  .lp
.yes:
    stc
    jmp  .out
.no:
    clc
.out:
    pop  di
    pop  si
    pop  ax
    ret

; =============================================================================
; Nombres de comandos
; =============================================================================
cmd_ver:      db 'ver', 0
cmd_clear:    db 'clear', 0
cmd_list:     db 'list', 0
cmd_make_dir: db 'make-dir', 0
cmd_exofetch: db 'exofetch', 0
cmd_sprusr:   db 'sprusr', 0
cmd_halt:     db 'halt', 0
