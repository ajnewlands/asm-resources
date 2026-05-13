# memcpyU256 — 256-bit AVX memcpy Implementation Walkthrough

## Overview

`memcpyU256` is a hand-optimized `memcpy` variant from Agner Fog's asmlib, targeting processors with fast unaligned reads and fast 256-bit (YMM) writes. It uses AVX `vmovups`/`vmovaps` instructions to move 32 bytes per loop iteration.

---

## Execution Flow

### 1. Prologue & Size Check

```asm
memcpyU256:
    PROLOGM                ; Save registers, normalize calling convention (Windows/Unix)
    cmp  rcx, 40H
    jb   A1000             ; If count < 64, use scalar/SSE fallback
```

Copies smaller than 64 bytes skip the AVX path entirely and use a simple descending-size move sequence (32-16-8-4-2-1 bytes).

### 2. Destination Alignment (B3020–B3060)

```asm
    mov  edx, edi
    neg  edx
    and  edx, 1FH          ; edx = bytes needed to align dest to 32-byte boundary
    jz   B3100             ; Skip if already aligned
```

`rdi` is the **destination** pointer (where data is written to). This section calculates how many bytes must be copied before `rdi` reaches the next 32-byte aligned address. The destination is aligned (not the source) because aligned *stores* (`vmovaps`) avoid split cache-line writes and maximize store-buffer throughput, while unaligned *loads* (`vmovups`) are essentially free on Sandy Bridge+ CPUs.

A bit-test cascade then copies the required bytes in the largest power-of-two chunks possible:

```asm
test dl, 1    → move 1 byte   if bit 0 set
test dl, 2    → move 2 bytes  if bit 1 set
test dl, 4    → move 4 bytes  if bit 2 set
test dl, 8    → move 8 bytes  if bit 3 set
test dl, 16   → move 16 bytes if bit 4 set
```

This is a binary decomposition of the alignment gap — any value 1–31 is handled in at most 5 moves. For example, if 28 bytes are needed (binary `11100`), it moves 4 + 8 + 16 bytes in just 3 operations, not 28 individual byte copies. Each step uses the widest operation available for its size (up to `movups xmm0` for 16 bytes).

### 3. Main Loop Setup (B3100)

```asm
    mov  rdx, rcx          ; Save remaining count
    and  rcx, -20H         ; Round down to multiple of 32
    add  rsi, rcx          ; Advance src pointer to end of loop region
    add  rdi, rcx          ; Advance dest pointer to end of loop region
    sub  rdx, rcx          ; rdx = leftover bytes after loop
    cmp  rcx, [CacheBypassLimit]
    ja   I3100             ; Branch to non-temporal path for very large copies
    neg  rcx               ; Convert to negative index (counts up to zero)
```

### 4. False Dependency Check (H3100)

```asm
    test sil, 1FH
    jz   H3110             ; Source already 32-byte aligned — no risk
    mov  eax, esi
    sub  eax, edi
    and  eax, 0FFFH        ; (src - dest) mod 4096
    cmp  eax, 1000H - 200H
    ja   J3100             ; Potential 4K aliasing — use backward copy
```

This detects a microarchitectural hazard called **4K aliasing** (store-to-load false dependency). Modern Intel CPUs use the low 12 bits of an address to speculatively predict whether a load depends on a prior store. In the main loop, we store to `[rdi+rcx]` then load from `[rsi+rcx]` on the next iteration. If `(rsi - rdi) mod 4096` is close to 4096 (within 512 bytes — the `200H`), the source and destination addresses have nearly identical low-12 bits, causing the CPU to stall the load on every iteration even though the addresses don't actually overlap.

The check is skipped if the source is already 32-byte aligned (`test sil, 1FH`), since in that case the low bits differ enough that aliasing can't occur.

When triggered, the code falls back to copying **backward** (high to low addresses at `J3100`), which reverses the store/load relationship and breaks the aliasing pattern.

**Why not always copy backward?** The forward path is faster in the common case because:
1. CPU hardware prefetchers are optimized for sequential forward access — they speculatively fetch upcoming cache lines. Backward iteration either disables this or relies on less efficient backward prefetch detection.
2. The backward path has extra setup overhead (overlap check, push/pop registers, pointer adjustment).

So forward is the fast default, and backward is a fallback only when the 4K aliasing penalty (stalling every loop iteration) would be worse than losing prefetch efficiency.

### 5. Main Copy Loop (H3110)

```asm
align 16
H3110:
    vmovups ymm0, [rsi+rcx]   ; Unaligned 32-byte load from source
    vmovaps [rdi+rcx], ymm0   ; Aligned 32-byte store to destination
    add     rcx, 20H
    jnz     H3110
    vzeroupper                 ; Transition out of AVX state
```

### 6. Remainder Handling (H3120)

Moves the leftover 0–31 bytes using a descending-size sequence: 16, 8, 4, 2, 1 bytes.

### 7. Non-Temporal Path (I3100/I3110)

When the copy size exceeds `CacheBypassLimit` (half the largest cache level, determined at runtime; defaults to 4 MB if undetectable), the code switches to non-temporal stores. This avoids polluting the cache — a large copy written through the normal path would evict virtually all hot data from L1/L2/L3 that surrounding code is actively using. Non-temporal stores write directly to memory without allocating cache lines, keeping the rest of the cache intact. The tradeoff is that the copied data itself won't be cached afterward, but for buffers this large it would be evicted by its own later portions anyway.

The threshold is set at half the last-level cache because copies that fit in cache *should* be cached (the destination may be read soon), but once the size exceeds that point, caching becomes pointless and destructive.

```asm
I3110:
    vmovups  ymm0, [rsi+rcx]
    vmovntps [rdi+rcx], ymm0   ; Write-combining, bypasses cache
    add      rcx, 20H
    jnz      I3110
    sfence                     ; Ensure NT stores are globally visible
    vzeroupper
    jmp      H3120
```

### 8. Backward Copy for 4K Aliasing (J3100/J3110)

If false dependency is detected and buffers don't overlap, copies in reverse order to avoid the stall.

---

## Performance Optimizations

| Optimization | Description |
|---|---|
| **Destination alignment** | The initial byte-shuffle aligns `rdi` to a 32-byte boundary so the main loop can use `vmovaps` (aligned store), which avoids split cache-line writes and enables full store-buffer throughput. |
| **Unaligned load / aligned store** | `vmovups` (load) tolerates misaligned source with negligible penalty on modern CPUs, while `vmovaps` (store) guarantees single-cycle commit to the aligned cache line. |
| **Negative-index loop** | Using a negative counter that increments toward zero eliminates a separate compare instruction — the `add` sets ZF directly, saving one µop per iteration. |
| **Loop alignment** | `align 16` before H3110 ensures the loop entry sits on a 16-byte boundary, preventing instruction fetch stalls and maximizing µop cache utilization. |
| **4K aliasing detection** | Checks `(src-dest) mod 4096` to detect false store-to-load dependencies. When triggered, falls back to a backward copy that avoids the penalty entirely. |
| **Non-temporal stores for large copies** | When the transfer size exceeds half the last-level cache (`CacheBypassLimit`), `vmovntps` bypasses the cache hierarchy, preventing pollution of L1/L2/L3 and saturating memory bandwidth. |
| **`sfence` only on NT path** | The serializing fence is issued only when non-temporal stores are used, avoiding unnecessary pipeline stalls on the normal path. |
| **`vzeroupper` on exit** | Clears the upper 128 bits of all YMM registers to prevent costly AVX-to-SSE transition penalties in subsequent code. |
| **Bit-test alignment cascade** | Uses `test dl, {1,2,4,8,16}` to conditionally move exact power-of-two chunks, avoiding branches on common aligned cases and minimizing total instructions for the preamble. |
| **Early-out checks** | `jz H3500` / `jz H500` after 8-byte moves skip remaining size checks when the count is evenly divisible, reducing branch mispredictions on common sizes. |
| **Backward copy avoidance** | Only copies backward when 4K aliasing is confirmed AND buffers don't overlap, keeping the common forward path as the fast default. |
| **32-byte granularity** | Matches the native YMM register width, maximizing throughput per iteration while keeping the loop body to just 3 instructions (load, store, add+branch fused). |

---

## Summary

The `memcpyU256` path is optimized for the common case: medium-to-large copies on CPUs with fast unaligned loads (Sandy Bridge and later). It achieves near-peak memory bandwidth by:

1. Minimizing alignment overhead with a branchless bit-cascade preamble
2. Running a tight 3-instruction inner loop at 32 bytes/iteration
3. Detecting and mitigating microarchitectural hazards (4K aliasing)
4. Switching to non-temporal stores for working sets that exceed cache capacity
