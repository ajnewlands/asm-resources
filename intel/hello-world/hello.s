; The traditional hello world program,
; without relying on the c standard library

section .data
NULL equ 0
LINEFEED equ 10
STDOUT equ 1
SYS_EXIT equ 60
SYS_WRITE equ 1
EXIT_SUCCESS equ 0

greeting db "Hello, world - what a wonderful day!", LINEFEED, NULL

section .text
global _start

  

_start:
  ; count message length
  mov rdi, greeting 
  
  ; determine the length of the string in rsi
  mov rsi, greeting
  mov rbx, rsi
  xor rdx, rdx ;zero counter
 

loop:
  cmp byte[rbx], NULL
  je done
  inc rbx
  inc rdx
  jmp loop
done:
  ; print message
  mov rax, SYS_WRITE
  mov rdi, STDOUT
  ; NB rsi == our message
  ; NB rdx == our message length
  syscall

  ; exit with return code 0 ('EXIT_SUCCESS')
  mov rax, SYS_EXIT
  mov rdi, EXIT_SUCCESS
  syscall
