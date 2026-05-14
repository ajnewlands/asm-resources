; Tags for chunks
QOI_OP_INDEX EQU 0x00
QOI_OP_DIFF EQU 0x40 ; b01000000
QOI_OP_LUMA EQU 0x80 ; b10000000
QOI_OP_RUN EQU 0xC0 ; b11000000
QOI_OP_RGB EQU 0xFE ; b11111110
QOI_OP_RGBA EQU 0xFF ; b11111111

section .rodata
align 16
; Weights for SIMD hash: (r*3 + g*5 + b*7 + a*11) computed via pmaddubsw
; pmaddubsw treats first operand as unsigned bytes, second as signed bytes,
; multiplies pairwise and adds adjacent pairs into 16-bit results.
; Layout: [3, 5, 7, 11, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
hash_weights: db 3, 5, 7, 11, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0

section .text
extern malloc
extern realloc
extern free
global qoi_encode_asm

; qoi_encode_asm(data: *const u8, width: u32, height: u32, out: *mut *mut u8) -> i64
; Linux calling convention: rdi=data, esi=width, edx=height, rcx=out
; Input must be RGBA (4 channels) and data pointer must be 32-byte aligned.
; Returns: rax = length of encoded data, or 0 on error (matching qoi_encode()
;  in the reference encoder).
;
; Register allocation during main loop:
;   rbx = input pointer (advances by 4 per pixel)
;   r12d = remaining pixel count (counts down to 0)
;   r13d = previous pixel (packed RGBA as u32, little-endian)
;   r14 = output write pointer (advances as chunks are emitted)
;   r15d = run count
;   [rbp-264] = buffer start address (for computing final length)
;   [rbp-272] = out pointer (for updating *out after realloc)
;   Index table accessed as [rbp - 256 + hash*4]
qoi_encode_asm:
    ; Save callee-saved registers BEFORE the frame pointer so that
    ; `leave` can restore rsp to just above them.
    push rbx
    push r12
    push r13
    push r14
    push r15

    ; Establish stack frame.
    push rbp
    mov rbp, rsp

    ; Verify data pointer is 32-byte aligned
    test rdi, 31
    jnz .error_early

    ; Move arguments into callee-saved registers so they survive calls.
    mov rbx, rdi        ; rbx = data pointer
    mov r12d, esi       ; r12d = width
    mov r13d, edx       ; r13d = height (temporary)
    mov r14, rcx        ; r14 = out pointer (temporary)

    ; Allocate 64-entry pixel index table on the stack (64 * 4 = 256 bytes)
    ; plus 8 bytes to store the buffer start address + 8 bytes for out pointer = 272 bytes.
    ; Zero-initialized. `leave` will reclaim this automatically.
    ; Index table: [rbp - 256 + hash * 4] where hash is 0..63
    ; Buffer start: [rbp - 264]
    ; Out pointer:  [rbp - 272]
    sub rsp, 272
    mov rdi, rsp
    xor eax, eax
    mov ecx, 34         ; 272 bytes / 8 = 34 qwords
    rep stosq

    ; Calculate worst case buffer size: 22 + width * height * 5
    ; (this is `max_size` in the reference qoi_encode function)
    mov eax, r12d       ; eax = width
    imul eax, r13d      ; eax = width * height
    lea edi, [rax*4+rax] ; edi = width*height*5
    add edi, 22         ; edi = 22 + width*height*5

    call malloc wrt ..plt

    test rax, rax
    jz .error

    ; Store allocated buffer pointer in *out and save on stack
    mov [r14], rax
    mov [rbp-264], rax
    ; Also save the out pointer itself so we can clear it on error
    mov [rbp-272], r14

    ; Write QOI header (14 bytes) into output buffer.
    ; see the qoi_header struct per https://qoiformat.org/qoi-specification.pdf
    mov dword [rax], 'qoif'     ; magic bytes
    bswap r12d                   ; convert width to big-endian
    mov [rax+4], r12d            ; width
    bswap r13d                   ; convert height to big-endian
    mov [rax+8], r13d            ; height
    mov byte [rax+12], 4         ; channels = 4 (RGBA)
    mov byte [rax+13], 0         ; colorspace = 0 (sRGB with linear alpha)

    ; Compute pixel count and set up registers for main loop.
    bswap r12d                   ; restore width to native order
    bswap r13d                   ; restore height to native order
    imul r12d, r13d              ; r12d = pixel count

    ; r14 = output write pointer, starting after the 14-byte header
    lea r14, [rax+14]

    ; r13d = previous pixel, initialized to rgba(0, 0, 0, 255)
    ; In memory: [0x00, 0x00, 0x00, 0xFF] = 0xFF000000 as little-endian u32
    mov r13d, 0xFF000000

    ; r15d = run count
    xor r15d, r15d

    ; Guard: skip loop if pixel count is zero
    test r12d, r12d
    jz .loop_end

    ; =========================================================================
    ; Main encoding loop (bottom-tested)
    ; =========================================================================
.loop:
    ; Load current pixel as u32
    mov eax, [rbx]

    ; Compare with previous pixel
    cmp eax, r13d
    jne .no_match

    ; Pixels match — increment run count
    inc r15d
    cmp r15d, 62
    jne .loop_tail

    ; Run count hit 62 — flush QOI_OP_RUN
    lea ecx, [r15d - 1 + QOI_OP_RUN]  ; tag | (run - 1)
    mov [r14], cl
    inc r14
    xor r15d, r15d
    jmp .loop_tail

.no_match:
    ; Flush any pending run before handling the new pixel
    test r15d, r15d
    jz .no_pending_run
    lea ecx, [r15d - 1 + QOI_OP_RUN]
    mov [r14], cl
    inc r14
    xor r15d, r15d

.no_pending_run:
    ; eax = current pixel (packed RGBA, little-endian: [r, g, b, a])
    ; r13d = previous pixel

    ; Compute hash: (r*3 + g*5 + b*7 + a*11) % 64 using SSSE3
    movd xmm0, eax
    pmaddubsw xmm0, [rel hash_weights]
    phaddw xmm0, xmm0          ; word0 = (r*3+g*5) + (b*7+a*11)
    movd ecx, xmm0
    and ecx, 63                ; % 64 = hash index

    ; Check index table
    lea rsi, [rbp-256]
    cmp eax, [rsi+rcx*4]
    je .emit_index

    ; Store current pixel in index table
    mov [rsi+rcx*4], eax

    ; Compute channel diffs (current - previous), truncated to signed 8-bit
    ; to match the reference encoder's signed char semantics.
    mov edx, eax               ; current pixel
    mov esi, r13d              ; previous pixel (clobbers rsi — table base no longer needed)
    movzx ecx, dl              ; cur.r
    movzx edi, sil             ; prev.r
    sub ecx, edi               ; dr (signed)
    movsx ecx, cl              ; truncate to signed char
    mov r8d, edx
    shr r8d, 8
    movzx r8d, r8b             ; cur.g
    mov edi, esi
    shr edi, 8
    movzx edi, dil             ; prev.g
    sub r8d, edi               ; dg (signed)
    movsx r8d, r8b             ; truncate to signed char
    mov edi, edx
    shr edi, 16
    movzx edi, dil             ; cur.b
    mov r9d, esi
    shr r9d, 16
    movzx r9d, r9b             ; prev.b
    sub edi, r9d               ; db (signed)
    movsx edi, dil             ; truncate to signed char
    mov r9d, edx
    shr r9d, 24                ; cur.a
    mov r10d, esi
    shr r10d, 24               ; prev.a
    sub r9d, r10d              ; da (signed)

    ; Update previous pixel
    mov r13d, eax

    ; If da != 0, must use QOI_OP_RGBA
    test r9d, r9d
    jnz .emit_rgba

    ; Try QOI_OP_DIFF: dr in [-2,1], dg in [-2,1], db in [-2,1]
    lea r10d, [ecx+2]          ; dr + 2 (should be 0..3)
    lea r11d, [r8d+2]          ; dg + 2 (should be 0..3)
    lea esi, [edi+2]           ; db + 2 (should be 0..3)
    cmp r10d, 3
    ja .try_luma
    cmp r11d, 3
    ja .try_luma
    cmp esi, 3
    ja .try_luma

    ; Emit QOI_OP_DIFF: 01 | dr+2 (2 bits) | dg+2 (2 bits) | db+2 (2 bits)
    shl r10d, 4                ; dr+2 << 4
    shl r11d, 2                ; dg+2 << 2
    or r10d, r11d
    or r10d, esi
    or r10d, QOI_OP_DIFF
    mov [r14], r10b
    inc r14
    jmp .loop_tail

.try_luma:
    ; QOI_OP_LUMA: dg in [-32,31], dr-dg in [-8,7], db-dg in [-8,7]
    lea r10d, [r8d+32]         ; dg + 32 (should be 0..63)
    cmp r10d, 63
    ja .emit_rgb
    mov esi, ecx
    sub esi, r8d               ; dr - dg
    lea r11d, [esi+8]          ; dr-dg + 8 (should be 0..15)
    cmp r11d, 15
    ja .emit_rgb
    mov esi, edi
    sub esi, r8d               ; db - dg
    lea esi, [esi+8]           ; db-dg + 8 (should be 0..15)
    cmp esi, 15
    ja .emit_rgb

    ; Emit QOI_OP_LUMA: byte1 = 10 | dg+32 (6 bits), byte2 = dr-dg+8 (4 bits) | db-dg+8 (4 bits)
    or r10d, QOI_OP_LUMA
    mov [r14], r10b
    shl r11d, 4
    or r11d, esi
    mov [r14+1], r11b
    add r14, 2
    jmp .loop_tail

.emit_rgb:
    ; Emit QOI_OP_RGB: tag (1) + r (1) + g (1) + b (1) = 4 bytes
    mov byte [r14], QOI_OP_RGB
    mov [r14+1], al            ; r
    mov ecx, eax
    shr ecx, 8
    mov [r14+2], cl            ; g
    shr ecx, 8
    mov [r14+3], cl            ; b
    add r14, 4
    jmp .loop_tail

.emit_rgba:
    ; Emit QOI_OP_RGBA: tag (1) + r (1) + g (1) + b (1) + a (1) = 5 bytes
    mov byte [r14], QOI_OP_RGBA
    mov [r14+1], eax
    add r14, 5
    jmp .loop_tail

.emit_index:
    ; Emit QOI_OP_INDEX: 00 | hash (6 bits)
    mov r13d, eax              ; update previous pixel
    mov [r14], cl              ; hash is already 0..63, top 2 bits are 00
    inc r14
    ; fall through to loop_tail

    ; =========================================================================
    ; Loop tail: advance input, decrement count, branch back if not done.
    ; =========================================================================
.loop_tail:
    add rbx, 4          ; advance input pointer
    dec r12d            ; decrement pixel count
    jnz .loop           ; loop while pixels remain

.loop_end:
    ; Flush any remaining run
    test r15d, r15d
    jz .no_final_run
    lea ecx, [r15d - 1 + QOI_OP_RUN]
    mov [r14], cl
    inc r14

.no_final_run:
    ; Write 8-byte end marker (7 zero bytes + 0x01)
    mov dword [r14], 0x00000000
    mov dword [r14+4], 0x01000000
    add r14, 8

    ; Return encoded length = write pointer - buffer start
    mov rax, r14
    sub rax, [rbp-264]

    ; Realloc buffer to actual encoded size
    mov rdi, [rbp-264]  ; ptr = buffer start
    mov rsi, rax        ; size = encoded length
    mov [rbp-272+8], rax ; save length temporarily (reuse a slot)
    push rax            ; preserve length across call
    call realloc wrt ..plt
    pop rcx             ; rcx = saved length
    test rax, rax
    jz .realloc_failed
    ; Update *out with the (possibly moved) pointer
    mov rdx, [rbp-272]
    mov [rdx], rax
    mov rax, rcx        ; return length
    jmp .done

.realloc_failed:
    ; realloc failed — original buffer is still valid, just return the length
    mov rax, rcx
    jmp .done

.error:
    ; Free the buffer if it was allocated (check if *out is non-null)
    mov rdi, [rbp-272]  ; out pointer location
    test rdi, rdi
    jz .error_no_free
    mov rdi, [rdi]      ; *out = buffer pointer
    test rdi, rdi
    jz .error_no_free
    sub rsp, 8          ; align stack for call
    call free wrt ..plt
    add rsp, 8
    ; Clear *out so caller doesn't use freed memory
    mov rdi, [rbp-272]
    mov qword [rdi], 0
.error_no_free:
    xor eax, eax
    jmp .done

.error_early:
    ; Error before stack frame is fully set up (no buffer allocated)
    xor eax, eax

.done:
    leave
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
