; =============================================================================
; BÚFERES Y PARSER DE ARGUMENTOS DENTRO DE XSH
; XSH - Shell (sin duplicados)
; XSH — Exokernel Shell [XSPEC-0006]
; Prompt nativo: |directorio| $
; Comandos: ver clear list make-dir make-file del read write cd pwd halt
; =============================================================================
[BITS 16]

; En la rutina xsh_leer_linea, separaremos la primera palabra (comando)
; del resto del texto (argumentos)

xsh_separar_argumentos:
    mov si, buffer_linea
    mov di, buffer_comando
    mov bp, buffer_argumentos

.copiar_cmd:
    lodsb
    cmp al, ' '
    je .inicio_args
    cmp al, 0
    je .fin_cmd
    stosb
    jmp .copiar_cmd

.fin_cmd:
    mov byte [di], 0
    mov byte [bp], 0
    ret

.inicio_args:
    mov byte [di], 0

.copiar_args:
    lodsb
    mov [bp], al
    inc bp
    cmp al, 0
    jne .copiar_args
    ret

; --- EN EL EVALUADOR DE COMANDOS DE XSH ---
.evaluar_comandos:
    call xsh_separar_argumentos

    ; Evaluar "make"
    mov si, buffer_comando
    mov di, cmd_make
    call xsh_comparar_cadenas
    je .ejecutar_make

    ; Evaluar "remove"
    mov si, buffer_comando
    mov di, cmd_remove
    call xsh_comparar_cadenas
    je .ejecutar_remove

    ; ... (otros comandos: sprusr, exofetch, xdt, xfl, etc.)

.ejecutar_make:
    call cmd_make_main
    jmp .mostrar_prompt

.ejecutar_remove:
    call cmd_remove_main
    jmp .mostrar_prompt

; --- DATOS Y BÚFERES ADICIONALES ---
cmd_make            db "make", 0
cmd_remove          db "remove", 0

buffer_comando     times 32 db 0
buffer_argumentos  times 64 db 0

; --- INCLUSIÓN DE ARCHIVOS DE MÓDULOS ---
%include "src/apps/xsh/sprusr.asm"
%include "src/apps/xsh/make.asm"
%include "src/apps/xsh/remove.asm"
%include "src/apps/exofetch.asm"
%include "src/apps/xdt.asm"
%include "src/apps/xfl.asm"
xsh_interactive_loop:
    mov si, msg_prompt
    call print_16_kernel   ; Usamos la versión del kernel
    jmp xsh_interactive_loop
XSH_BUF_LEN  equ 255
XSH_ARGC_MAX equ 8
XSH_ARG_LEN  equ 64

msg_prompt db "|$ ", 0
xsh_linebuf:  times XSH_BUF_LEN + 1 db 0
xsh_args:     times XSH_ARGC_MAX * XSH_ARG_LEN db 0
xsh_argc:     dq 0
xsh_cwd_name: times 128 db 0
write_databuf: times 512 db 0
read_databuf:  times 512 db 0

; Tabla de comandos: (puntero nombre, puntero funcion), termina en 0,0
cmd_table:
    dq str_cmd_ver,       xsh_cmd_ver
    dq str_cmd_clear,     xsh_cmd_clear
    dq str_cmd_list,      xsh_cmd_list
    dq str_cmd_make_dir,  xsh_cmd_make_dir
    dq str_cmd_make_file, xsh_cmd_make_file
    dq str_cmd_del,       xsh_cmd_del
    dq str_cmd_read,      xsh_cmd_read
    dq str_cmd_write,     xsh_cmd_write
    dq str_cmd_cd,        xsh_cmd_cd
    dq str_cmd_pwd,       xsh_cmd_pwd
    dq str_cmd_halt,      xsh_cmd_halt
    dq 0, 0

str_cmd_ver:        db 'ver', 0
str_cmd_clear:       db 'clear', 0
str_cmd_list:        db 'list', 0
str_cmd_make_dir:    db 'make-dir', 0
str_cmd_make_file:   db 'make-file', 0
str_cmd_del:         db 'del', 0
str_cmd_read:        db 'read', 0
str_cmd_write:       db 'write', 0
str_cmd_cd:          db 'cd', 0
str_cmd_pwd:         db 'pwd', 0
str_cmd_halt:        db 'halt', 0
str_dotdot:          db '..', 0

msg_xsh_ver:
    db 'XSH v0.1 -- XOS Exokernel Shell', 10
    db 'Sin POSIX. Sin UNIX. Sin GNU.', 10
    db 'Comandos: ver clear list make-dir make-file del read write cd pwd halt', 10, 0

msg_prompt_l:     db '|', 0
msg_prompt_r:     db '| $ ', 0
msg_unknown_cmd:  db 'XSH: comando no reconocido. Escribe "ver" para ayuda.', 10, 0
msg_missing_arg:  db 'XSH: falta argumento.', 10, 0
msg_err_exists:   db 'XSH: ya existe.', 10, 0
msg_err_notfound: db 'XSH: no encontrado.', 10, 0
msg_err_nospace:  db 'XSH: sin espacio en disco.', 10, 0
msg_created:      db 'XSH: creado.', 10, 0
msg_deleted:      db 'XSH: eliminado.', 10, 0
msg_halt_msg:     db 10, 'XOS: sistema detenido. Hasta luego.', 10, 0
msg_write_done:   db 10, 'XSH: escrito.', 10, 0
msg_read_start:   db 10, '--- contenido ---', 10, 0
msg_read_end:     db '--- fin ---', 10, 0

; -----------------------------------------------------------------------
; PUNTO DE ENTRADA DEL SHELL
; -----------------------------------------------------------------------
global xsh_main
xsh_main:
    lea  rdi, [rel xsh_cwd_name]
    mov  byte [rdi], '|'
    mov  byte [rdi+1], 0

.loop:
    mov  bl, 0x0A
    mov  rsi, msg_prompt_l
    call xk_print

    lea  rsi, [rel xsh_cwd_name]
    call xk_print

    mov  rsi, msg_prompt_r
    call xk_print

    lea  rdi, [rel xsh_linebuf]
    mov  rcx, XSH_BUF_LEN
    call xk_readline

    lea  rsi, [rel xsh_linebuf]
    call xsh_parse_args

    cmp  qword [xsh_argc], 0
    je   .loop

    call xsh_dispatch
    jmp  .loop

; -----------------------------------------------------------------------
; xsh_parse_args — separa xsh_linebuf en argumentos por espacios
; -----------------------------------------------------------------------
xsh_parse_args:
    push rax
    push rbx
    push rcx
    push rdi
    push rsi

    mov  qword [xsh_argc], 0
    xor  rbx, rbx

.skip_spaces:
    mov  al, [rsi]
    test al, al
    jz   .done
    cmp  al, ' '
    jne  .copy_arg
    inc  rsi
    jmp  .skip_spaces

.copy_arg:
    cmp  rbx, XSH_ARGC_MAX
    jge  .done

    lea  rdi, [rel xsh_args]
    mov  rax, rbx
    imul rax, XSH_ARG_LEN
    add  rdi, rax

    mov  rcx, XSH_ARG_LEN - 1
.copy_char:
    mov  al, [rsi]
    test al, al
    jz   .arg_done
    cmp  al, ' '
    je   .arg_done
    test rcx, rcx
    jz   .arg_done
    mov  [rdi], al
    inc  rdi
    inc  rsi
    dec  rcx
    jmp  .copy_char

.arg_done:
    mov  byte [rdi], 0
    inc  rbx
    inc  qword [xsh_argc]
    jmp  .skip_spaces

.done:
    pop  rsi
    pop  rdi
    pop  rcx
    pop  rbx
    pop  rax
    ret

%macro ARG 1
    lea rsi, [rel xsh_args + %1 * XSH_ARG_LEN]
%endmacro

; -----------------------------------------------------------------------
; xsh_dispatch — busca arg[0] en cmd_table y llama la funcion
; -----------------------------------------------------------------------
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
    mov  rax, [rbx + 8]
    call rax
    jmp  .done

.unknown:
    mov  rsi, msg_unknown_cmd
    mov  bl,  0x0C
    call xk_print

.done:
    pop  rdi
    pop  rsi
    pop  rbx
    pop  rax
    ret

; =========================================================================
; COMANDOS
; =========================================================================

xsh_cmd_ver:
    mov  rsi, msg_xsh_ver
    mov  bl,  0x0B
    call xk_print
    ret

xsh_cmd_clear:
    call xk_init_video
    ret

xsh_cmd_list:
    call exfs_list_dir
    ret

xsh_cmd_make_dir:
    cmp  qword [xsh_argc], 2
    jl   .noarg
    ARG 1
    mov  bl, XOBJ_DIR
    call exfs_make_obj
    test rax, rax
    jz   .ok
    cmp  rax, -2
    je   .exists
    mov  rsi, msg_err_nospace
    mov  bl,  0x0C
    call xk_print
    ret
.ok:
    mov  rsi, msg_created
    mov  bl,  0x0A
    call xk_print
    ret
.exists:
    mov  rsi, msg_err_exists
    mov  bl,  0x0E
    call xk_print
    ret
.noarg:
    mov  rsi, msg_missing_arg
    mov  bl,  0x0C
    call xk_print
    ret

xsh_cmd_make_file:
    cmp  qword [xsh_argc], 2
    jl   .noarg
    ARG 1
    mov  bl, XOBJ_DOCUMENT
    call exfs_make_obj
    test rax, rax
    jz   .ok
    cmp  rax, -2
    je   .exists
    mov  rsi, msg_err_nospace
    mov  bl,  0x0C
    call xk_print
    ret
.ok:
    mov  rsi, msg_created
    mov  bl,  0x0A
    call xk_print
    ret
.exists:
    mov  rsi, msg_err_exists
    mov  bl,  0x0E
    call xk_print
    ret
.noarg:
    mov  rsi, msg_missing_arg
    mov  bl,  0x0C
    call xk_print
    ret

xsh_cmd_del:
    cmp  qword [xsh_argc], 2
    jl   .noarg
    ARG 1
    call exfs_delete_obj
    test rax, rax
    jz   .ok
    mov  rsi, msg_err_notfound
    mov  bl,  0x0C
    call xk_print
    ret
.ok:
    mov  rsi, msg_deleted
    mov  bl,  0x0A
    call xk_print
    ret
.noarg:
    mov  rsi, msg_missing_arg
    mov  bl,  0x0C
    call xk_print
    ret

xsh_cmd_read:
    cmp  qword [xsh_argc], 2
    jl   .noarg
    ARG 1
    push rsi
    mov  rsi, msg_read_start
    mov  bl,  0x0E
    call xk_print
    pop  rsi

    lea  rdi, [rel read_databuf]
    call exfs_read_obj_data
    cmp  rax, -1
    je   .notfound

    lea  rsi, [rel read_databuf]
    mov  byte [rsi + rax], 0
    mov  bl,  0x0F
    call xk_print

    mov  rsi, msg_read_end
    mov  bl,  0x0E
    call xk_print
    ret
.notfound:
    mov  rsi, msg_err_notfound
    mov  bl,  0x0C
    call xk_print
    ret
.noarg:
    mov  rsi, msg_missing_arg
    mov  bl,  0x0C
    call xk_print
    ret

xsh_cmd_write:
    cmp  qword [xsh_argc], 3
    jl   .noarg

    lea  rdi, [rel write_databuf]
    xor  rbx, rbx
    mov  rcx, [xsh_argc]
    mov  r8,  2

.concat:
    cmp  r8, rcx
    jge  .write_it
    cmp  r8, 2
    je   .no_space_first
    mov  byte [rdi + rbx], ' '
    inc  rbx
.no_space_first:
    push r8
    push rcx
    mov  rax, r8
    imul rax, XSH_ARG_LEN
    lea  rsi, [rel xsh_args]
    add  rsi, rax
    pop  rcx
    pop  r8
.copy:
    mov  al, [rsi]
    test al, al
    jz   .arg_end
    mov  [rdi + rbx], al
    inc  rsi
    inc  rbx
    cmp  rbx, 511
    jge  .arg_end
    jmp  .copy
.arg_end:
    inc  r8
    jmp  .concat

.write_it:
    mov  byte [rdi + rbx], 0

    ARG 1
    lea  rdi, [rel write_databuf]
    mov  rcx, rbx
    call exfs_write_obj_data
    cmp  rax, -1
    je   .notfound

    mov  rsi, msg_write_done
    mov  bl,  0x0A
    call xk_print
    ret
.notfound:
    mov  rsi, msg_err_notfound
    mov  bl,  0x0C
    call xk_print
    ret
.noarg:
    mov  rsi, msg_missing_arg
    mov  bl,  0x0C
    call xk_print
    ret

xsh_cmd_cd:
    cmp  qword [xsh_argc], 2
    jl   .noarg

    ARG 1
    mov  rdi, str_dotdot
    call xk_strcmp
    test rax, rax
    jz   .go_parent

    ARG 1
    mov  rcx, XOBJ_DIR
    call exfs_find_obj
    cmp  rax, -1
    je   .notfound

    mov  eax, ebx
    lea  rdi, [rel exfs_io_buf]
    call exfs_ata_read

    mov  rax, rdx
    shl  rax, 6
    lea  rdi, [rel exfs_io_buf]
    add  rdi, rax

    mov  eax, [rdi + 0x28]
    mov  [exfs_cur_dir_lba], rax

    lea  rsi, [rdi + 0x04]
    lea  rdi, [rel xsh_cwd_name]
    mov  rcx, 127
    call xk_strncpy
    ret

.go_parent:
    mov  qword [exfs_cur_dir_lba], EXFS_DATA_LBA
    lea  rdi, [rel xsh_cwd_name]
    mov  byte [rdi], '|'
    mov  byte [rdi+1], 0
    ret

.notfound:
    mov  rsi, msg_err_notfound
    mov  bl,  0x0C
    call xk_print
    ret
.noarg:
    mov  rsi, msg_missing_arg
    mov  bl,  0x0C
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
    mov  bl,  0x0C
    call xk_print
    cli
    hlt
    jmp $
