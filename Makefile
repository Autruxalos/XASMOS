# =============================================================================
# MAKEFILE - XASMOS EXOKERNEL OPERATING SYSTEM
# =============================================================================
# IMPORTANTE — arquitectura de build:
#   src/kernel/xkernel.asm es el UNICO archivo que se ensambla como kernel.
#   Integra src/drivers/exfs.asm, src/init/exit.asm y src/apps/xsh.asm
#   mediante %include, porque el formato `-f bin` de NASM no tiene linker:
#   NO se pueden ensamblar exit.asm/xsh.asm/exfs.asm por separado, si se hace
#   fallan con "symbol not defined" porque cada .bin queda aislado.
#
# Mapa de disco:
#   Sector 0      -> XBOOT   (MBR, 512 bytes exactos)
#   Sector 1..64  -> XKERNEL (hasta 32 KB, incluye EXFS+EXIT+XSH)
#   Sector 38+    -> Datos EXFS (formateados en caliente por el kernel)
# =============================================================================

ASM      = nasm
ASMFLAGS = -f bin -w+all -Werror=zeroing

BOOT_SRC   = src/boot/xboot.asm
KERNEL_SRC = src/kernel/xkernel.asm

# Dependencias: si cualquiera de estos cambia, el kernel debe recompilarse
KERNEL_DEPS = $(KERNEL_SRC) \
              src/drivers/exfs.asm \
              src/init/exit.asm \
              src/apps/xsh.asm

BOOT_BIN   = bin/xboot.bin
KERNEL_BIN = bin/xkernel.bin

IMAGE      = xos.img
IMAGE_SECTORS = 8192          # 4 MB de imagen total

QEMU     = qemu-system-x86_64
QEMUFLAGS = -m 64M -no-reboot -no-shutdown

.PHONY: all run debug clean info

all: $(IMAGE)

bin:
	@mkdir -p bin

# --- XBOOT: debe ser exactamente 512 bytes con firma 0xAA55 ---
$(BOOT_BIN): $(BOOT_SRC) | bin
	@echo "[NASM] XBOOT..."
	$(ASM) $(ASMFLAGS) $(BOOT_SRC) -o $(BOOT_BIN)
	@sz=$$(wc -c < $(BOOT_BIN)); \
	if [ $$sz -ne 512 ]; then \
		echo "ERROR: XBOOT tiene $$sz bytes (debe ser 512)"; exit 1; \
	fi
	@sig=$$(od -An -tx1 -j 510 -N 2 $(BOOT_BIN) | tr -d ' '); \
	if [ "$$sig" != "55aa" ]; then \
		echo "ERROR: firma MBR incorrecta ($$sig, esperada 55aa)"; exit 1; \
	fi
	@echo "      XBOOT OK (512 bytes, firma 0xAA55)"

# --- XKERNEL: incluye EXFS + EXIT + XSH en un solo binario plano ---
$(KERNEL_BIN): $(KERNEL_DEPS) | bin
	@echo "[NASM] XKERNEL (+ EXFS + EXIT + XSH via %include)..."
	$(ASM) $(ASMFLAGS) $(KERNEL_SRC) -o $(KERNEL_BIN)
	@sz=$$(wc -c < $(KERNEL_BIN)); \
	maxsz=$$((64 * 512)); \
	if [ $$sz -gt $$maxsz ]; then \
		echo "ERROR: XKERNEL ocupa $$sz bytes, excede los $$maxsz reservados"; \
		echo "       (sube KERNEL_SECTORS en el Makefile y en XBOOT)"; exit 1; \
	fi
	@echo "      XKERNEL OK ($$(wc -c < $(KERNEL_BIN)) bytes)"

# --- Imagen de disco final ---
$(IMAGE): $(BOOT_BIN) $(KERNEL_BIN)
	@echo ""
	@echo "[IMG] Creando $(IMAGE) ($(IMAGE_SECTORS) sectores = $$(( $(IMAGE_SECTORS)*512/1024/1024 )) MB)..."
	dd if=/dev/zero of=$(IMAGE) bs=512 count=$(IMAGE_SECTORS) status=none
	dd if=$(BOOT_BIN)   of=$(IMAGE) bs=512 seek=0 count=1 conv=notrunc status=none
	@echo "      [sector 0] XBOOT"
	dd if=$(KERNEL_BIN) of=$(IMAGE) bs=512 seek=1 conv=notrunc status=none
	@echo "      [sector 1] XKERNEL ($$(( ($$(wc -c < $(KERNEL_BIN)) + 511) / 512 )) sectores)"
	@echo ""
	@echo "[OK] $(IMAGE) listo. Usa 'make run' para ejecutar."

# --- Ejecutar en QEMU ---
run: $(IMAGE)
	@echo "[QEMU] Iniciando XOS..."
	$(QEMU) -drive format=raw,file=$(IMAGE),if=ide,media=disk $(QEMUFLAGS) -display sdl

# --- Ejecutar en modo texto (sin SDL, util en servidores/SSH) ---
run-nographic: $(IMAGE)
	@echo "[QEMU] Iniciando XASMOS (modo serial/consola)..."
	$(QEMU) -drive format=raw,file=$(IMAGE),if=ide,media=disk $(QEMUFLAGS) -display curses

# --- Debug: monitor de QEMU + log de interrupciones/resets ---
debug: $(IMAGE)
	@echo "[QEMU] Modo debug -- Ctrl+Alt+2 para el monitor"
	$(QEMU) -drive format=raw,file=$(IMAGE),if=ide,media=disk $(QEMUFLAGS) \
		-monitor stdio -d int,cpu_reset -D qemu_debug.log -display sdl

info:
	@echo "XBOOT:   $$(wc -c < $(BOOT_BIN) 2>/dev/null || echo '(no compilado)') bytes"
	@echo "XKERNEL: $$(wc -c < $(KERNEL_BIN) 2>/dev/null || echo '(no compilado)') bytes"
	@echo "IMAGE:   $$(wc -c < $(IMAGE) 2>/dev/null || echo '(no generada)') bytes"

clean:
	@echo "[CLEAN] Eliminando binarios e imagen..."
	rm -rf bin/
	rm -f $(IMAGE) qemu_debug.log
	@echo "      Listo."
