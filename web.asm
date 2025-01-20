format ELF64 executable

SYS_SOCKET = 41
SYS_CLOSE = 3
SYS_EXIT = 60
SYS_WRITE = 1
SYS_READ = 0
SYS_BIND = 49
SYS_LISTEN = 50
SYS_ACCEPT = 43

STDOUT = 1
STDERR = 2

MAX_REQEUST = 64*1024 ; 64kB


macro close socket
{
    mov rax, SYS_CLOSE
    mov rdi, socket
    syscall
}

macro write fd, buf, count
{
    mov rax, SYS_WRITE
    mov rdi, fd
    mov rsi, buf
    mov rdx, count
    syscall
}

macro read fd, buf, count
{
    mov rax, SYS_READ
    mov rdi, fd
    mov rsi, buf
    mov rdx, count
    syscall
}


macro exit_error socket, connection
{
    ;; Clean up socket
    close socket
    close connection

    mov rax, SYS_EXIT
    mov rdi, 1
    syscall
}


macro socket domain, type, protocol
{
    mov rax, SYS_SOCKET
    mov rdi, domain
    mov rsi, type
    mov rdx, protocol
    syscall
}

macro bind socket, struct, size_struct
{
    mov rax, SYS_BIND
    mov rdi, socket
    mov rsi, struct
    mov rdx, size_struct
    syscall
}

macro listen socket, backlog
{
    mov rax, SYS_LISTEN
    mov rdi, socket
    mov rsi, backlog
    syscall
}

macro accept socket, addr, addrlen
{
    mov rax, SYS_ACCEPT
    mov rdi, socket
    mov rsi, addr
    mov rdx, addrlen
    syscall
}

segment readable executable
entry main

;; https://www.geeksforgeeks.org/tcp-server-client-implementation-in-c/
;; Loosely implemented

main:
    write STDOUT, start, start_len ; Log starting message to stdout

    ;; sockfd = socket(AF_INET, SOCK_STREAM, 0);
    socket 2, 1, 0 ; Opening iPv4 TCP
    cmp rax, 0  ; Check for error
    jl error_socket

    mov qword [sockfd], rax ;  specify we are moving 2 bytes result (therefore using eax)
    
    ;;    servaddr.sin_family = AF_INET; 
    ;;    servaddr.sin_addr.s_addr = htonl(INADDR_ANY); // INADDR_ANY = 0
    ;;    servaddr.sin_port = htons(PORT);  // htons reverses byte order

    mov word [servaddr.sin_family], 2 ; Populate with AF_INET
    mov dword [servaddr.sin_addr], 0 ; no need to reverse endian, since 0
    mov dword [servaddr.sin_port], 3879 ; 9999 -> 0x270F, which in network order is 0x0F27 -> 3879

    ;; bind(sockfd, (SA*)&servaddr, sizeof(servaddr))
    bind [sockfd], servaddr.sin_family, size_servaddr ; Following struct logic, we just point at start elem of struct
    cmp rax, 0
    jl .error_bind

    ;; listen(sockfd, 5) // Where 5 is the backlog of connections
    listen [sockfd], 5
    cmp rax, 0
    jl .error_listen


.next: ; Handle continous 
    ;; // Accept the data packet from client and verification 
    ;; connfd = accept(sockfd, (SA*)&cli, &len); 
    accept [sockfd], cli.sin_family, cli_len
    cmp rax, 0
    jl .error_accept
    mov qword [connfd], rax ; Move the connection into memory from rax

;; Get the request:
    read [connfd], request, MAX_REQEUST
    cmp rax, 0
    jl .error_read

    mov [request_len], rax
    mov [curr_request], request

    write STDOUT, [curr_request], [request_len]

    ;; Loading to prepare for starts_with
    mov rdi, [curr_request]
    mov rsi, [request_len]
    mov rdx, get_prefix
    mov r10, get_prefix_len
    call starts_with

    cmp rax, 0 
    jg .handle_get ; If it is a get request, serve the content

    ;; Loading to prepare for starts_with
    mov rdi, [curr_request]
    mov rsi, [request_len]
    mov rdx, post_prefix
    mov r10, post_prefix_len
    call starts_with

    cmp rax, 0 
    jg .shutdown ; If it is a post request, shutdown the server

    write [connfd], unsupported_req, unsupported_req_len
    write STDERR, unsupported_req_msg, unsupported_req_msg_len
    jmp .next

.handle_get
    write [connfd], response, response_len
    jmp .next

.shutdown
    write STDOUT, server_closing_msg, server_closing_msg_len
    close [sockfd]
    close [connfd]
    mov rax, SYS_EXIT
    mov rdi, 0
    syscall


;; Errors:
.error_socket:
    write STDERR, error_sock_msg, error_sock_msg_len 
    exit_error [sockfd], [connfd]

.error_bind:
    write STDERR, error_bind_msg, error_bind_msg_len
    exit_error [sockfd], [connfd]

.error_listen:
    write STDERR, error_listen_msg, error_listen_msg_len
    exit_error [sockfd], [connfd]

.error_accept:
    write STDERR, error_accept_msg, error_accept_msg_len
    exit_error [sockfd], [connfd]

.error_read:
    write STDERR, error_read_msg, error_read_msg_lenm
    exit_error [sockfd], [connfd]


;; Helper Functions:

;; inputs: | rdi   | rsi      | rdx     | r10        |
;;         | *text | text_len | *prefix | prefix_len |
starts_with:
    xor rax, rax ; Clear rax and rbx
    xor rbx, rbx
.next: 
    cmp rsi, 0 ; Check remaining text len 
    jle .done ; Finish if no text left
    cmp r10, 0 ; check prefix len
    jle .done

    mov al, byte [rdi] ;  move current text byte
    mov bl, byte [rdx] ;  move current prefix byte
    cmp rax, rbx
    jne .done ; if not equal, exit

    dec rsi ; decrement remaining text len
    inc rdi ; move to next byte in text

    dec r10 ; decrement remaining prefix len
    inc rdx ; move to next byte in prefix

    jmp .next

.done 
    cmp r10, 0 
    je .yes ; If we have reached here with an empty prefix len, they must match
    mov rax, 0 ; Otherwise, load error
    ret 
.yes 
    mov rax, 1 ; Load Success
    ret


;; Memory
segment readable writable

;; Constants etc:
start db "Web Server Starting", 10
start_len = $ - start

error_sock_msg db "Error Creating Socket", 10
error_sock_msg_len = $ - error_sock_msg

error_bind_msg db "Error Binding Socket", 10
error_bind_msg_len = $ - error_bind_msg

error_listen_msg db "Listen failed...", 10
error_listen_msg_len = $ - error_listen_msg

error_accept_msg db "Server Accept Failed", 10
error_accept_msg_len = $ - error_accept_msg

unsupported_req_msg db "Unsupported HTTP Request Received, Ignoring", 10
unsupported_req_msg_len = $ - unsupported_req_msg

server_closing_msg db "INFO: Server Shutting Down. Good Night!", 10
server_closing_msg_len = $ - server_closing_msg

response    db "HTTP/1.1 200 OK", 13, 10
            db "Content-Type: text/html", 13, 10
            db "Connection: close", 13, 10
            db 13, 10 
            db "<!DOCTYPE html><html><head>", 13, 10
            db "<title>Assembly Webserver</title>", 13, 10
            db "<style>", 13, 10
            db "body{background-color:#f0f0f0;", 13, 10
            db "text-align:center;font-family:Arial;}", 13, 10
            db "h1{color:#0FF;}", 13, 10
            db "</style>", 13, 10
            db "</head><body>", 13, 10
            db "<h1>My Webserver in Assembly!</h1>", 13, 10
            db "</body></html>", 13, 10, 0

response_len = $ - response


unsupported_req     db "HTTP/1.1 405 Method Not Allowed", 13, 10
                    db "Content-Type: text/html", 13, 10
                    db "Content-Length: 160", 13, 10
                    db "Connection: close", 13, 10
                    db 13, 10 
                    db "<!DOCTYPE html><html><head>", 13, 10
                    db "<title>Assembly Webserver</title>", 13, 10
                    db "</head><body>", 13, 10
                    db "<h1>Unsupported Request</h1>", 13, 10
                    db "<a href='/'>Go Back</a>", 13, 10
                    db "</body></html>", 0



;; Mutable Data
sockfd dq -1
connfd dq -1

;; servaddr struct
servaddr.sin_family dw 0
servaddr.sin_port dw 0
servaddr.sin_addr dd 0
servaddr.sin_zero dq 0
size_servaddr = $ - servaddr.sin_family ; size of first elem

;; cli struct
cli.sin_family dw 0
cli.sin_port dw 0
cli.sin_addr dd 0
cli.sin_zero dq 0
size_cli = $ - cli.sin_family ; size of first elem
cli_len dd size_cli

;; Requests
request_len rq 1
curr_request rq 1
request rb MAX_REQEUST