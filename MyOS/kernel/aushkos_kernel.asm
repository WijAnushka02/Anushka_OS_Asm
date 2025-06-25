BITS 16
ORG 0x0000

start:
    ; Initialize segment registers and stack for the kernel
    cli                                 ; Disable interrupts during segment setup
    mov ax, 0x2000                      ; Set AX to the kernel's base segment
    mov ds, ax                          ; Set Data Segment to kernel's base
    mov es, ax                          ; Set Extra Segment to kernel's base
    mov ss, ax                          ; Set Stack Segment to kernel's base
    mov sp, 0x7C00                      ; Set Stack Pointer to 0x7C00 (within the 0x2000 segment)
                                        ; Stack will grow downwards from 0x2000:0x7C00
    sti                                 ; Enable interrupts

    call clear_screen                   ; Clear the display before printing anything

    ; --- Added: Initial Boot Messages (moved from bootloader) ---
    mov si, bios_version_msg            ; e.g., "SeaBIOS (version 1.13.0-lubuntul)"
    call print_string
    call print_newline

    mov si, ipxe_msg                    ; e.g., "iPXE (http://ipxe.org) ..."
    call print_string
    call print_newline

    mov si, booting_floppy_msg          ; "Booting from Floppy..." (simulated message for kernel)
    call print_string
    call print_newline

    mov si, loading_boot_image_msg      ; "Loading Boot Image" (simulated message for kernel)
    call print_string
    call print_newline
    ; --- End Added ---

    mov si, welcome_msg                 ; Load the address of the "Welcome AushkOS Aushk>>" message into SI
    call print_string                   ; Call the subroutine to print the string

main_loop:
    call print_newline                  ; Print a new line for better readability
    mov si, prompt                      ; Load the address of the command prompt string ("> ") into SI
    call print_string                   ; Print the prompt

    call clear_input                    ; Clear the input buffer before reading new input
    call read_line                      ; Read user input from the keyboard into the input_buffer

    mov si, input_buffer                ; Load the address of the user's input into SI
    mov di, info_cmd                    ; Load the address of the "info" command string into DI
    mov cx, 4                           ; Set CX to 4 (length of "info" command)
    repe cmpsb                          ; Repeat Compare String Byte while equal (ZF=1) and CX > 0
    je show_info                        ; If input matches "info", jump to show_info subroutine

    ; If the command was not "info"
    mov si, unknown                     ; Load the address of the "Unknown command!" message into SI
    call print_string                   ; Print the unknown command message
    jmp main_loop                       ; Jump back to the beginning of the main_loop to prompt again

show_info:
    call print_newline                  ; Print a new line before displaying hardware details

    ; --- 1. Base Memory Detection (Conventional Memory) ---
    mov ah, 0x88                        ; AH=0x88, Get extended memory size (for conventional memory)
    int 0x15                            ; Call BIOS interrupt 0x15
    mov si, mem_msg                     ; Load "Base Memory: " string
    call print_string                   ; Print the label
    call print_ax                       ; Print the value in AX (base memory in KB) as hex
    mov si, kb                          ; Load "KB" string
    call print_string                   ; Print "KB"
    call print_newline                  ; New line

    ; --- 2. Extended Memory Detection (Memory above 1MB) ---
    mov ax, 0xE801                      ; AX=0xE801, Get extended memory size for 1MB+
    int 0x15                            ; Call BIOS interrupt 0x15

    push ax                             ; Save AX (memory 1-16MB)
    push bx                             ; Save BX (memory >16MB)

    ; Print memory between 1MB and 16MB
    mov si, xmem_1_16mb_msg             ; Load "Extended Memory (1-16MB): " string
    call print_string                   ; Print the label
    pop bx                              ; Restore BX (memory >16MB) - important for next step
    pop ax                              ; Restore AX (memory 1-16MB) - important for print_ax
    call print_ax                       ; Print AX (1-16MB memory in KB) as hex
    mov si, kb                          ; Load "KB" string
    call print_string                   ; Print "KB"
    call print_newline                  ; New line

    ; Print memory above 16MB
    mov si, xmem_over16mb_msg           ; Load "Extended Memory (>16MB): " string
    call print_string                   ; Print the label
    mov ax, bx                          ; Move BX (memory >16MB) to AX for the print_ax subroutine
    call print_ax                       ; Print AX (>16MB memory in KB) as hex
    mov si, kb                          ; Load "KB" string
    call print_string                   ; Print "KB"
    call print_newline                  ; New line

    ; --- 3. CPU Vendor String Detection (CPUID Instruction) ---
    call cpuid                          ; Call subroutine to get CPUID info and store vendor string
    mov si, cpu_label                   ; Load "CPU Vendor: " string
    call print_string                   ; Print the label
    mov si, cpuid_ebx                   ; Load address of the EBX part of the vendor string
    call print_4                        ; Print 4 characters (first part of vendor string)
    mov si, cpuid_edx                   ; Load address of the EDX part
    call print_4                        ; Print 4 characters (second part)
    mov si, cpuid_ecx                   ; Load address of the ECX part
    call print_4                        ; Print 4 characters (third part)
    call print_newline                  ; New line

    ; --- 4. Serial Port (COM1) Check ---
    mov si, serial_msg                  ; Load "Serial Port: " string
    call print_string                   ; Print the label
    mov dx, 0x03F8                      ; COM1 base address (Data Register)
    in al, dx                           ; Attempt to read from serial port
    mov si, serial_found                ; Load "Found" message
    call print_string                   ; Print "Found"
    call print_newline

    ; --- 5. Hard Drive Detection ---
    mov si, hdd_msg                     ; Load "Hard Drive: " string
    call print_string                   ; Print the label
    mov dl, 0x80                        ; DL=0x80 for first hard disk
    mov ah, 0x15                        ; AH=0x15, INT 13h: Get drive type
    int 0x13                            ; Call BIOS interrupt 0x13
    cmp ah, 0                           ; Check AH register. AH=0 on success.
    jne .no_disk                        ; If AH is not 0, no hard disk found.
    cmp al, 2                           ; AL=0 for no disk, AL=1 for floppy, AL=2 for hard disk.
    jb .no_disk                         ; If AL < 2 (0 or 1), it's not a hard disk.
    mov si, hdd_found                   ; Hard drive found
    jmp .done                           ; Jump to .done to print the message
.no_disk:
    mov si, hdd_none                    ; No hard drive found
.done:
    call print_string                   ; Print the hard drive status message
    call print_newline                  ; New line
    jmp main_loop                       ; Jump back to the main_loop to prompt for the next command

; ------------------------------------------------------------------
; KERNEL SUBROUTINES
; ------------------------------------------------------------------

print_char:
    mov ah, 0x0E
    int 0x10
    ret

print_string:
    pusha
.next_char:
    lodsb
    or al, al
    jz .done_printing
    call print_char
    jmp .next_char
.done_printing:
    popa
    ret

print_newline:
    mov ah, 0x0E
    mov al, 13
    int 0x10
    mov al, 10
    int 0x10
    ret

print_ax:
    pusha
    mov cx, 4
.hex_digit_loop:
    rol ax, 4
    mov bl, al
    and bl, 0x0F
    cmp bl, 9
    jbe .is_digit
    add bl, 7
.is_digit:
    add bl, '0'
    mov al, bl
    call print_char
    loop .hex_digit_loop
    popa
    ret

print_4:
    mov cx, 4
.char_loop:
    lodsb
    call print_char
    loop .char_loop
    ret

clear_screen:
    mov ax, 0x0600
    mov bh, 0x07
    mov cx, 0x0000
    mov dx, 0x184F
    int 0x10
    ret

clear_input:
    mov cx, 32
    mov di, input_buffer
    xor al, al
    rep stosb
    ret

read_line:
    xor bx, bx
    mov di, input_buffer
.read_char:
    mov ah, 0
    int 0x16
    cmp al, 13
    je .end_read
    cmp al, 8
    je .handle_backspace
    cmp bx, 31
    ja .read_char
    mov ah, 0x0E
    int 0x10
    stosb
    inc bx
    jmp .read_char
.handle_backspace:
    cmp bx, 0
    je .read_char
    dec bx
    dec di
    mov ah, 0x0E
    mov al, 8
    int 0x10
    mov al, ' '
    int 0x10
    mov al, 8
    int 0x10
    jmp .read_char
.end_read:
    mov al, 0
    stosb
    ret

; ------------------------------------------------------------------
; Data Section: Strings and Variables
; ------------------------------------------------------------------

; Messages
; These are simulated BIOS/Bootloader messages printed by the kernel for effect.
bios_version_msg    db "SeaBIOS (version 1.13.0-lubuntul)", 0
ipxe_msg            db "iPXE (http://ipxe.org) 00:03.0 CA00 PCl2.10 PnP PMM+07F8C1300+07ECCA00 CR00", 0
booting_floppy_msg  db "Booting from Floppy...", 0
loading_boot_image_msg db "Loading Boot Image", 0

welcome_msg     db "Welcome AushkOS Aushk>> ", 0 ; Changed to AushkOS
prompt          db "> ", 0
info_cmd        db "info", 0
unknown         db " Unknown command!", 0

; Input Buffer
input_buffer    times 32 db 0

; Hardware Info Labels
mem_msg         db "Base Memory: ", 0
xmem_1_16mb_msg db "Extended Memory (1-16MB): ", 0
xmem_over16mb_msg db "Extended Memory (>16MB): ", 0
cpu_label       db "CPU Vendor: ", 0
serial_msg      db "Serial Port: ", 0
serial_found    db "Found", 0
hdd_msg         db "Hard Drive: ", 0
hdd_found       db "Found", 0
hdd_none        db "None", 0
kb              db "KB", 0

; Variables for CPUID results
cpuid_ebx       dd 0
cpuid_ecx       dd 0
cpuid_edx       dd 0

; --- CPUID Subroutine (placed here as it uses DWORD variables directly) ---
cpuid:
    pushfd
    pushfd
    pop eax
    mov ecx, eax
    xor eax, 0x00200000
    push eax
    popfd
    pushfd
    pop eax
    xor eax, ecx
    je .no_cpuid
    mov eax, 0
    cpuid
    mov [cpuid_ebx], ebx
    mov [cpuid_ecx], ecx
    mov [cpuid_edx], edx
    jmp .done_cpuid
.no_cpuid:
    xor eax, eax
    mov [cpuid_ebx], eax
    mov [cpuid_ecx], eax
    mov [cpuid_edx], eax
.done_cpuid:
    popfd
    ret