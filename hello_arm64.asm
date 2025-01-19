format MACHO64 executable

segment readable executable
entry main

main:
    mov x16, 0x2000004 ; macOS syscall number for write
    mov x0, 1
    ldr x1, =msg
    mov x2, msg_len
    svc #0x80

    mov x16, 0x2000001 ; macOS syscall number for exit
    mov x0, 0
    svc #0x80

segment readable writable
msg db "Hello, World!", 10
msg_len = $ - msg