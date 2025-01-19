format ELF64 executable

SYS_SOCKET = 41
SYS_EXIT = 60
SYS_WRITE = 1

STDOUT = 1
STDERR = 2

macro write fd, buf, count
{
    mov rax, SYS_WRITE
    mov rdi, fd
    mov rsi, buf
    mov rdx, count
    syscall
}

;; equivalent to standard C `int socket()`
macro socket domain, type, protocol
{
    mov rax, SYS_SOCKET
    mov rdi, domain
    mov rsi, type
    mov rdx, protocol
    syscall
}



segment readable executable
entry main

main:
    write STDOUT, start, start_len ; Log starting message to stdout
    socket 2, 1, 0 ; Opening iPv4 TCP

    cmp rax, 0  ; Check for error
    jl error_socket

    mov dword [sockfd], eax ;  specify we are moving 2 bytes result (therefore using eax)
    
;; EXIT
    mov rax, SYS_EXIT
    mov rdi, 0
    syscall

error_socket:
    write STDERR, error_sock_msg, error_sock_msg_len 
;; EXIT
    mov rax, SYS_EXIT
    mov rdi, 1
    syscall

;; Constants etc:
segment readable writable
start db "Web Server Starting", 10
start_len = $ - start
error_sock_msg db "Error Creating Socket", 10
error_sock_msg_len = $ - error_sock_msg
sockfd dd 0