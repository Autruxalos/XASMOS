; =============================================================================
; XSH — Exokernel Shell [XSPEC-0006] (Optimizada multi-modo)
; Compatible 16-bit (8086/286) como mínimo. También corre en 32/64.
; Prompt:  &>>  (usuario)   |   (>>  (sprusr)
; Comandos: ver clear list make-dir make-file del read write cd pwd halt
;           sprusr exofetch
; =============================================================================
[BITS 16]                       ; ← Solo 16-bit. Es lo que garantiza compatibilidad

; ---------------------------------------------------------------------------
; Constantes y buffers
; ---------------------------------------------------------------------------
XSH_BUF_LEN  equ 80
XSH_ARGC_MAX equ 8
XSH_ARG_LEN  equ 32

xsh_linebuf:      times XSH_BUF_LEN+1 db 0
xsh_args:         times XSH_ARGC_MAX * XSH_ARG_LEN db 0
xsh_argc:         db 0
xsh_cwd_name:     db '|', 0
                  times 31 db 0
xsh_is_sprusr:    db 0                  ; 0 = usuario, 1 = sprusr

write_databuf:    times 256 db 0
read_databuf:     times 256 db 0

; ---------------------------------------------------------------------------
; Mensajes
; ---------------------------------------------------------------------------
msg_prompt_user:  db ' &>> ', 0
msg_prompt_root:  db ' (>> ', 0
msg_prompt_l:     db '|', 0
msg_prompt_r:     db '|', 0

msg_xsh_ver:
    db 'XSH v0.2 -- XOS Exokernel Shell (16-bit)', 13, 10
    db 'Sin POSIX. Sin UNIX. Sin GNU.', 13, 10
    db 'Comandos: ver clear list make-dir make-file del read write cd pwd halt sprusr exofetch', 13, 10, 0

msg_unknown_cmd:  db 'XSH: comando no reconocido. Escribe "ver" para ayuda.', 13, 10, 0
msg_missing_arg:  db 'XSH: falta argumento.', 13, 10, 0
msg_err_exists:   db 'XSH: ya existe.', 13, 10, 0
msg_err_notfound: db 'XSH: no encontrado.', 13, 10, 0
msg_err_nospace:  db 'XSH: sin espacio en disco.', 13, 10, 0
msg_created:      db 'XSH: creado.', 13, 10, 0
msg_deleted:      db 'XSH: eliminado.', 13, 10, 0
msg_halt_msg:     db 13, 10, 'XOS: sistema detenido. Hasta luego.', 13, 10, 0
msg_write_done:   db 13, 10, 'XSH: escrito.', 13, 10, 0
msg_read_start:   db 13, 10, '--- contenido ---', 13, 10, 0
msg_read_end:     db '--- fin ---', 13, 10, 0
msg_sprusr_ok:    db 'Modo sprusr activado', 13, 10, 0

; ---------------------------------------------------------------------------
; Nombres de comandos
; ---------------------------------------------------------------------------
str_cmd_ver:        db 'ver', 0
str_cmd_clear:      db 'clear', 0
str_cmd_list:       db 'list', 0
str_cmd_make_dir:   db 'make-dir', 0
str_cmd_make_file:  db 'make-file', 0
str_cmd_del:        db 'del', 0
str_cmd_read:       db 'read', 0
str_cmd_write:      db 'write', 0
str_cmd_cd:         db 'cd', 0
str_cmd_pwd:        db 'pwd', 0
str_cmd_halt:       db 'halt', 0
str_cmd_sprusr:     db 'sprusr', 0
str_cmd_exofetch:   db 'exofetch', 0
str_dotdot:         db '..', 0

; ---------------------------------------------------------------------------
; Tabla de comandos (nombre, función)
; ---------------------------------------------------------------------------
cmd_table:
    dw str_cmd_ver,       xsh_cmd_ver
    dw str_cmd_clear,     xsh_cmd_clear
    dw str_cmd_list,      xsh_cmd_list
    dw str_cmd_make_dir,  xsh_cmd_make_dir
    dw str_cmd_make_file, xsh_cmd_make_file
    dw str_cmd_del,       xsh_cmd_del
    dw str_cmd_read,      xsh_cmd_read
    dw str_cmd_write,     xsh_cmd_write
    dw str_cmd_cd,        xsh_cmd_cd
    dw str_cmd_pwd,       xsh_cmd_pwd
    dw str_cmd_halt,      xsh_cmd_halt
    dw str_cmd_sprusr,    xsh_cmd_sprusr
    dw str_cmd_exofetch,  xsh_cmd_exofetch
    dw 0, 0

; =============================================================================
; Punto de entrada
; =============================================================================
global xsh_main
xsh_main:
    mov byte [xsh_cwd_name], '|'
    mov byte [xsh_cwd_name+1], 0
    mov byte [xsh_is_sprusr], 0

.loop:
    ; Prompt dinámico
    cmp byte [xsh_is_sprusr], 1
    je  .root_prompt
    mov si, msg_prompt_user
    jmp .show_prompt
.root_prompt:
    mov si, msg_prompt_root
.show_prompt:
    call xsh_print16

    ; Leer línea
    call xsh_read_line

    ; ¿Vacía?
    cmp byte [xsh_linebuf], 0
    je  .loop

    ; Parsear y despachar
    call xsh_parse_args
    cmp byte [xsh_argc], 0
    je  .loop
    call xsh_dispatch
    jmp .loop

; =============================================================================
; Lectura de línea (BIOS INT 0x16)
; =============================================================================
xsh_read_line:
    push ax
    push bx
    push si
    mov  si, xsh_linebuf
    xor  bx, bx

.read:
    xor  ah, ah
    int  0x16

    cmp  al, 13                 ; Enter
    je   .done
    cmp  al, 8                  ; Backspace
    je   .bs
    cmp  al, 27                 ; ESC → limpiar
    je   .clear

    cmp  bx, XSH_BUF_LEN-1
    jge  .read
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
    mov  [si], al
    inc  si
    inc  bx

    mov  ah, 0x0E
    mov  bh, 0
    int  0x10
    jmp  .read

.bs:
    test bx, bx
    jz   .read
    dec  si
    dec  bx
    mov  byte [si], 0
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
; Parser de argumentos (16-bit)
; =============================================================================
xsh_parse_args:
    push ax
    push bx
    push cx
    push si
    push di

    mov  byte [xsh_argc], 0
    xor  bx, bx
    mov  si, xsh_linebuf

.skip_spaces:
    mov  al, [si]
    test al, al
    jz   .done
    cmp  al, ' '
    jne  .copy_arg
    inc  si
    jmp  .skip_spaces

.copy_arg:
    cmp  bx, XSH_ARGC_MAX
    jge  .done

    ; di = xsh_args + bx * XSH_ARG_LEN
    mov  ax, bx
    mov  cx, XSH_ARG_LEN
    mul  cx
    lea  di, [xsh_args]
    add  di, ax

    mov  cx, XSH_ARG_LEN-1
.copy_char:
    mov  al, [si]
    test al, al
    jz   .arg_done
    cmp  al, ' '
    je   .arg_done
    test cx, cx
    jz   .arg_done
    mov  [di], al
    inc  di
    inc  si
    dec  cx
    jmp  .copy_char

.arg_done:
    mov  byte [di], 0
    inc  bx
    inc  byte [xsh_argc]
    jmp  .skip_spaces

.done:
    pop  di
    pop  si
    pop  cx
    pop  bx
    pop  ax
    ret

; Macro para obtener arg[N] en SI
%macro ARG 1
    mov  ax, %1
    mov  cx, XSH_ARG_LEN
    mul  cx
    lea  si, [xsh_args]
    add  si, ax
%endmacro

; =============================================================================
; Dispatcher
; =============================================================================
xsh_dispatch:
    push ax
    push bx
    push si
    push di

    ARG 0
    mov  di, si                 ; di = nombre del comando

    mov  bx, cmd_table
.search:
    mov  ax, [bx]               ; puntero al nombre
    test ax, ax
    jz   .unknown
    mov  si, ax
    push di
    call strcmp16
    pop  di
    jc   .found                 ; Carry = iguales
    add  bx, 4                  ; siguiente entrada (2 words)
    jmp  .search

.found:
    mov  ax, [bx+2]             ; dirección de la función
    call ax
    jmp  .done

.unknown:
    mov  si, msg_unknown_cmd
    call xsh_print16

.done:
    pop  di
    pop  si
    pop  bx
    pop  ax
    ret

; =============================================================================
; Comandos
; =============================================================================
xsh_cmd_ver:
    mov  si, msg_xsh_ver
    call xsh_print16
    ret

xsh_cmd_clear:
    mov  ax, 0x0003
    int  0x10
    ret; Antes: 

xsh_cmd_list:
    ; call exfs_list_dir (versión 16-bit)
    ret

xsh_cmd_make_dir:
    cmp  byte [xsh_argc], 2
    jl   .noarg
    ARG 1
    ; mov bl, XOBJ_DIR
    ; call exfs_make_obj
    mov  si, msg_created
    call xsh_print16
    ret
.noarg:
    mov  si, msg_missing_arg
    call xsh_print16
    ret

xsh_cmd_make_file:
    cmp  byte [xsh_argc], 2
    jl   .noarg
    ARG 1
    ; mov bl, XOBJ_DOCUMENT
    ; call exfs_make_obj
    mov  si, msg_created
    call xsh_print16
    ret
.noarg:
    mov  si, msg_missing_arg
    call xsh_print16
    ret

xsh_cmd_del:
    cmp  byte [xsh_argc], 2
    jl   .noarg
    ARG 1
    ; call exfs_delete_obj
    mov  si, msg_deleted
    call xsh_print16
    ret
.noarg:
    mov  si, msg_missing_arg
    call xsh_print16
    ret

xsh_cmd_read:
    cmp  byte [xsh_argc], 2
    jl   .noarg
    ARG 1
    mov  si, msg_read_start
    call xsh_print16
    ; call exfs_read_obj_data
    mov  si, msg_read_end
    call xsh_print16
    ret
.noarg:
    mov  si, msg_missing_arg
    call xsh_print16
    ret

xsh_cmd_write:
    cmp  byte [xsh_argc], 3
    jl   .noarg
    ; construir texto y llamar a exfs_write_obj_data
    mov  si, msg_write_done
    call xsh_print16
    ret
.noarg:
    mov  si, msg_missing_arg
    call xsh_print16
    ret

xsh_cmd_cd:
    cmp  byte [xsh_argc], 2
    jl   .noarg
    ARG 1
    ; lógica de cambio de directorio
    ret
.noarg:
    mov  si, msg_missing_arg
    call xsh_print16
    ret

xsh_cmd_pwd:
    mov  si, msg_prompt_l
    call xsh_print16
    mov  si, xsh_cwd_name
    call xsh_print16
    mov  si, msg_prompt_l
    call xsh_print16
    mov  ah, 0x0E
    mov  al, 13
    int  0x10
    mov  al, 10
    int  0x10
    ret

xsh_cmd_halt:
    mov  si, msg_halt_msg
    call xsh_print16
    cli
    hlt
    jmp  $

xsh_cmd_sprusr:
    mov  byte [xsh_is_sprusr], 1
    mov  si, msg_sprusr_ok
    call xsh_print16
    ret

xsh_cmd_exofetch:
    ; call exofetch_main_16
    ret

; =============================================================================
; Utilidades 16-bit
; =============================================================================
xsh_print16:
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
