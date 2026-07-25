; =============================================================================
; XSH — Exokernel Shell [XSPEC-0006]
; Prompt:  &>>  (usuario)   |   (>>  (sprusr)
; Comandos: ver clear list make-dir make-file del read write cd pwd
;           halt sprusr exofetch
; Teclado: PS/2 embebido (sin archivo externo)
; =============================================================================
[BITS 64]

; ---------------------------------------------------------------------------
; Constantes y buffers
; ---------------------------------------------------------------------------
XSH_BUF_LEN  equ 80
XSH_ARGC_MAX equ 8
XSH_ARG_LEN  equ 32

xsh_linebuf:   times XSH_BUF_LEN+1 db 0
xsh_args:      times XSH_ARGC_MAX * XSH_ARG_LEN db 0
xsh_argc:      dq 0
xsh_cwd_name:  db '|', 0
               times 31 db 0
xsh_is_sprusr: db 0

; ---------------------------------------------------------------------------
; Mensajes
; ---------------------------------------------------------------------------
msg_prompt_user:  db ' &>> ', 0
msg_prompt_root:  db ' (>> ', 0
msg_prompt_l:     db '|', 0

msg_xsh_ver:
    db 'XSH v0.3 -- XOS Exokernel Shell', 10
    db 'Sin POSIX. Sin UNIX. Sin GNU.', 10
    db 'Comandos: ver clear list make-dir make-file del read write cd pwd halt sprusr exofetch', 10, 0

msg_unknown_cmd:  db 'XSH: comando no reconocido. Escribe "ver".', 10, 0
msg_missing_arg:  db 'XSH: falta argumento.', 10, 0
msg_created:      db 'XSH: creado.', 10, 0
msg_deleted:      db 'XSH: eliminado.', 10, 0
msg_halt_msg:     db 10, 'XOS: sistema detenido.', 10, 0
msg_write_done:   db 10, 'XSH: escrito.', 10, 0
msg_read_start:   db 10, '--- contenido ---', 10, 0
msg_read_end:     db '--- fin ---', 10, 0
msg_sprusr_ok:    db 'Modo sprusr activado', 10, 0

; ---------------------------------------------------------------------------
; Nombres de comandos
; ---------------------------------------------------------------------------
str_ver:        db 'ver', 0
str_clear:      db 'clear', 0
str_list:       db 'list', 0
str_make_dir:   db 'make-dir', 0
str_make_file:  db 'make-file', 0
str_del:        db 'del', 0
str_read:       db 'read', 0
str_write:      db 'write', 0
str_cd:         db 'cd', 0
str_pwd:        db 'pwd', 0
str_halt:       db 'halt', 0
str_sprusr:     db 'sprusr', 0
str_exofetch:   db 'exofetch', 0

; ---------------------------------------------------------------------------
; Tabla de comandos
; ---------------------------------------------------------------------------
cmd_table:
    dq str_ver,       xsh_cmd_ver
    dq str_clear,     xsh_cmd_clear
    dq str_list,      xsh_cmd_list
    dq str_make_dir,  xsh_cmd_make_dir
    dq str_make_file, xsh_cmd_make_file
    dq str_del,       xsh_cmd_del
    dq str_read,      xsh_cmd_read
    dq str_write,     xsh_cmd_write
    dq str_cd,        xsh_cmd_cd
    dq str_pwd,       xsh_cmd_pwd
    dq str_halt,      xsh_cmd_halt
    dq str_sprusr,    xsh_cmd_sprusr
    dq str_exofetch,  xsh_cmd_exofetch
    dq 0, 0

; =============================================================================
; Mapa de scancodes (PS/2 set 1)
; =============================================================================
xsh_scancode_map:
    db 0, 0
    db '1','2','3','4','5','6','7','8','9','0','-','=', 8, 9
    db 'q','w','e','r','t','y','u','i','o','p','[',']', 13, 0
    db 'a','s','d','f','g','h','j','k','l',';',"','`', 0, 92
    db 'z','x','c','v','b','n','m',',','.','/', 0, 0, 0, 32
    times (128 - ($ - xsh_scancode_map)) db 0

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
    mov  bl, 0x0A
    mov  rsi, msg_prompt_user
    cmp  byte [xsh_is_sprusr], 1
    jne  .show
    mov  bl, 0x0C
    mov  rsi, msg_prompt_root
.show:
    call xk_print

    ; Leer línea
    call xsh_read_line

    cmp  byte [xsh_linebuf], 0
    je   .loop

    call xsh_parse_args
    cmp  qword [xsh_argc], 0
    je   .loop

    call xsh_dispatch
    jmp  .loop

; =============================================================================
; Lectura de teclado PS/2 (embebida)
; =============================================================================
xsh_read_line:
    push rax
    push rbx
    push rcx
    push rsi
    push rdi

    lea  rdi, [rel xsh_linebuf]
    xor  rbx, rbx

.wait:
    in   al, 0x64
    test al, 1
    jz   .wait

    in   al, 0x60
    test al, 0x80
    jnz  .wait

    movzx rcx, al
    cmp  rcx, 128
    jge  .wait

    lea  rsi, [rel xsh_scancode_map]
    mov  al, [rsi + rcx]
    test al, al
    jz   .wait

    cmp  al, 13
    je   .enter

    cmp  al, 8
    je   .backspace

    cmp  rbx, XSH_BUF_LEN-1
    jge  .wait

    mov  [rdi + rbx], al
    inc  rbx

    mov  bl, 0x0F
    call xk_putchar
    jmp  .wait

.backspace:
    test rbx, rbx
    jz   .wait
    dec  rbx
    mov  byte [rdi + rbx], 0

    mov  al, 8
    mov  bl, 0x07
    call xk_putchar
    mov  al, ' '
    call xk_putchar
    mov  al, 8
    call xk_putchar
    jmp  .wait

.enter:
    mov  byte [rdi + rbx], 0
    mov  al, 10
    mov  bl, 0x07
    call xk_putchar

    pop  rdi
    pop  rsi
    pop  rcx
    pop  rbx
    pop  rax
    ret

; =============================================================================
; Parser
; =============================================================================
xsh_parse_args:
    push rax
    push rbx
    push rcx
    push rsi
    push rdi

    mov  qword [xsh_argc], 0
    xor  rbx, rbx
    lea  rsi, [rel xsh_linebuf]

.skip:
    mov  al, [rsi]
    test al, al
    jz   .done
    cmp  al, ' '
    jne  .copy
    inc  rsi
    jmp  .skip

.copy:
    cmp  rbx, XSH_ARGC_MAX
    jge  .done

    lea  rdi, [rel xsh_args]
    mov  rax, rbx
    imul rax, XSH_ARG_LEN
    add  rdi, rax

    mov  rcx, XSH_ARG_LEN-1
.cchar:
    mov  al, [rsi]
    test al, al
    jz   .argend
    cmp  al, ' '
    je   .argend
    test rcx, rcx
    jz   .argend
    mov  [rdi], al
    inc  rdi
    inc  rsi
    dec  rcx
    jmp  .cchar

.argend:
    mov  byte [rdi], 0
    inc  rbx
    inc  qword [xsh_argc]
    jmp  .skip

.done:
    pop  rdi
    pop  rsi
    pop  rcx
    pop  rbx
    pop  rax
    ret

%macro ARG 1
    lea rsi, [rel xsh_args + %1 * XSH_ARG_LEN]
%endmacro

; =============================================================================
; Dispatcher
; =============================================================================
xsh_dispatch:
    push rax
    push rbx
    push rsi
    push rdi

    ARG 0
    mov  rdi, rsi

    lea  rbx, [rel cmd_table]
.search:
    mov  rax, [rbx]
    test rax, rax
    jz   .unknown

    mov  rsi, rax
    push rdi
    call xk_strcmp
    pop  rdi
    test rax, rax
    jz   .found

    add  rbx, 16
    jmp  .search

.found:
    mov  rax, [rbx+8]
    call rax
    jmp  .done

.unknown:
    mov  rsi, msg_unknown_cmd
    mov  bl, 0x0C
    call xk_print

.done:
    pop  rdi
    pop  rsi
    pop  rbx
    pop  rax
    ret

; =============================================================================
; Comandos
; =============================================================================
xsh_cmd_ver:
    mov  rsi, msg_xsh_ver
    mov  bl, 0x0B
    call xk_print
    ret

xsh_cmd_clear:
    call xk_init_video
    ret

xsh_cmd_list:
    ; call exfs_list_dir
    ret

xsh_cmd_make_dir:
    cmp  qword [xsh_argc], 2
    jl   .noarg
    ARG 1
    mov  rsi, msg_created
    mov  bl, 0x0A
    call xk_print
    ret
.noarg:
    mov  rsi, msg_missing_arg
    mov  bl, 0x0C
    call xk_print
    ret

xsh_cmd_make_file:
    cmp  qword [xsh_argc], 2
    jl   .noarg
    ARG 1
    mov  rsi, msg_created
    mov  bl, 0x0A
    call xk_print
    ret
.noarg:
    mov  rsi, msg_missing_arg
    mov  bl, 0x0C
    call xk_print
    ret

xsh_cmd_del:
    cmp  qword [xsh_argc], 2
    jl   .noarg
    ARG 1
    mov  rsi, msg_deleted
    mov  bl, 0x0A
    call xk_print
    ret
.noarg:
    mov  rsi, msg_missing_arg
    mov  bl, 0x0C
    call xk_print
    ret

xsh_cmd_read:
    cmp  qword [xsh_argc], 2
    jl   .noarg
    ARG 1
    mov  rsi, msg_read_start
    mov  bl, 0x0E
    call xk_print
    mov  rsi, msg_read_end
    call xk_print
    ret
.noarg:
    mov  rsi, msg_missing_arg
    mov  bl, 0x0C
    call xk_print
    ret

xsh_cmd_write:
    cmp  qword [xsh_argc], 3
    jl   .noarg
    mov  rsi, msg_write_done
    mov  bl, 0x0A
    call xk_print
    ret
.noarg:
    mov  rsi, msg_missing_arg
    mov  bl, 0x0C
    call xk_print
    ret

xsh_cmd_cd:
    cmp  qword [xsh_argc], 2
    jl   .noarg
    ARG 1
    ret
.noarg:
    mov  rsi, msg_missing_arg
    mov  bl, 0x0C
    call xk_print
    ret

xsh_cmd_pwd:
    mov  bl, 0x0B
    mov  rsi, msg_prompt_l
    call xk_print
    lea  rsi, [rel xsh_cwd_name]
    call xk_print
    mov  rsi, msg_prompt_l
    call xk_println
    ret

xsh_cmd_halt:
    mov  rsi, msg_halt_msg
    mov  bl, 0x0C
    call xk_print
    cli
    hlt
    jmp  $

xsh_cmd_sprusr:
    mov  byte [xsh_is_sprusr], 1
    mov  rsi, msg_sprusr_ok
    mov  bl, 0x0C
    call xk_print
    ret

xsh_cmd_exofetch:
    ; Aquí irá exofetch real
    ret
