
import math
import random 
def to_q15(x):
    v = int(round(x*32768))
    return max(-32768, min(32767, v))

def bitrev(x, bits):
    r = 0
    for i in range(bits):
        r = (r<<1) | (x&1)
        x >>= 1
    return r

def make_twiddle_table(sizes):
    table = {}
    for size in sizes:
        entries = []
        for k in range(size//2):
            ang = -2*math.pi*k/size
            entries.append((to_q15(math.cos(ang)), to_q15(math.sin(ang))))
        table[size] = entries
    return table

def butterfly(a_re,a_im,b_re,b_im,tw_re,tw_im):
    bw_re = ((b_re*tw_re)>>15) - ((b_im*tw_im)>>15)
    bw_im = ((b_re*tw_im)>>15) + ((b_im*tw_re)>>15)
    return (a_re+bw_re)>>1, (a_im+bw_im)>>1, (a_re-bw_re)>>1, (a_im-bw_im)>>1

def fft_scheme_A(samples, N, bits, twiddle_table, log=None):
    """natural storage, bit-reversed ACCESS addressing"""
    stages = bits
    re = list(samples); im=[0]*N
    for stage in range(1, stages+1):
        size = 1<<stage; half=size//2; num_groups=N//size
        if log is not None: log.append(f"-- Stage {stage} (size={size}) --")
        for g in range(num_groups):
            for k in range(half):
                a_nat = g*size+k; b_nat = a_nat+half
                a = bitrev(a_nat,bits); b = bitrev(b_nat,bits)
                twr,twi = twiddle_table[size][k]
                ar,ai,br,bi = re[a],im[a],re[b],im[b]
                oar,oai,obr,obi = butterfly(ar,ai,br,bi,twr,twi)
                if log is not None:
                    log.append(f"  g={g:3d} k={k:3d} | nat(a={a_nat:3d},b={b_nat:3d}) -> addr(a={a:3d},b={b:3d}) | "
                               f"in(A={ar:6d}+{ai:6d}j, B={br:6d}+{bi:6d}j) tw=({twr},{twi}) -> "
                               f"out(A'={oar:6d}+{oai:6d}j, B'={obr:6d}+{obi:6d}j)")
                re[a],im[a] = oar,oai
                re[b],im[b] = obr,obi
    out_re=[re[bitrev(i,bits)] for i in range(N)]
    out_im=[im[bitrev(i,bits)] for i in range(N)]
    print(f"Alternative algorithm: {out_re}, {out_im}")
    return out_re,out_im

def fft_scheme_B(samples, N, bits, twiddle_table, log=None):
    """standard DIT: permute input by bit-reversal, natural addressing thereafter"""
    stages=bits
    re=[0]*N; im=[0]*N
    for i in range(N):
        re[bitrev(i,bits)] = samples[i]
    if log is not None: log.append(f"-- Input bit-reversal permutation applied --")
    for stage in range(1,stages+1):
        size=1<<stage; half=size//2; num_groups=N//size
        if log is not None: log.append(f"-- Stage {stage} (size={size}) --")
        for g in range(num_groups):
            for k in range(half):
                a=g*size+k; b=a+half
                twr,twi = twiddle_table[size][k]
                ar,ai,br,bi = re[a],im[a],re[b],im[b]
                oar,oai,obr,obi = butterfly(ar,ai,br,bi,twr,twi)
                if log is not None:
                    log.append(f"  g={g:3d} k={k:3d} | addr(a={a:3d},b={b:3d}) | "
                               f"in(A={ar:6d}+{ai:6d}j, B={br:6d}+{bi:6d}j) tw=({twr},{twi}) -> "
                               f"out(A'={oar:6d}+{oai:6d}j, B'={obr:6d}+{obi:6d}j)")
                re[a],im[a]=oar,oai
                re[b],im[b]=obr,obi
    print( f"Original algorithm: {re}, {im}")
    return re,im

def run_comparison(N, out_lines):
    bits = N.bit_length()-1
    assert (1<<bits)==N, "N must be power of 2"
    sizes = [1<<s for s in range(1,bits+1)]
    twiddle_table = make_twiddle_table(sizes)

    # test signal: impulse at index 0
    samples = [to_q15(random.random()) for i in range(N)] 

    logA=[]; logB=[]
    outA_re,outA_im = fft_scheme_A(samples, N, bits, twiddle_table, log=logA)
    outB_re,outB_im = fft_scheme_B(samples, N, bits, twiddle_table, log=logB)

    match = (outA_re==outB_re) and (outA_im==outB_im)

    out_lines.append(f"{'='*70}")
    out_lines.append(f"N = {N} (bits={bits}) -- Scheme A vs Scheme B comparison")
    out_lines.append(f"{'='*70}")
    out_lines.append("")
    out_lines.append(f"[Scheme A: natural storage, bit-reversed ACCESS addressing -- YOUR RTL's approach]")
    out_lines.extend(logA[:40])
    if len(logA) > 40:
        out_lines.append(f"  ... ({len(logA)-40} more lines omitted for brevity) ...")
    out_lines.append("")
    out_lines.append(f"[Scheme B: standard DIT, bit-reverse INPUT then natural addressing -- textbook approach]")
    out_lines.extend(logB[:40])
    if len(logB) > 40:
        out_lines.append(f"  ... ({len(logB)-40} more lines omitted for brevity) ...")
    out_lines.append("")
    out_lines.append(f"Final output identical between schemes: {match}")
    if match:
        out_lines.append(f"First 8 output bins (re, im), both schemes agree:")
        for i in range(min(8,N)):
            out_lines.append(f"  bin {i}: re={outA_re[i]}, im={outA_im[i]}")
    else:
        out_lines.append("MISMATCH -- schemes disagree, listing differences:")
        for i in range(N):
            if outA_re[i]!=outB_re[i] or outA_im[i]!=outB_im[i]:
                out_lines.append(f"  bin {i}: A=({outA_re[i]},{outA_im[i]})  B=({outB_re[i]},{outB_im[i]})")
    out_lines.append("")
    return match

all_lines = []
all_lines.append("FFT ADDRESSING SCHEME COMPARISON LOG")
all_lines.append("Scheme A = your RTL's approach (natural storage + bit-reversed access)")
all_lines.append("Scheme B = textbook approach (bit-reverse input, natural addressing)")
all_lines.append("Test input: impulse (sample 0 = near full scale, rest = 0)")
all_lines.append("")

results = {}
for N in [8, 16, 32, 64, 128, 256]:
    results[N] = run_comparison(N, all_lines)

all_lines.append("="*70)
all_lines.append("SUMMARY")
all_lines.append("="*70)
for N, ok in results.items():
    all_lines.append(f"  N={N:4d}: {'MATCH (schemes equivalent)' if ok else 'MISMATCH'}")

with open("fft_comparison_log.txt","w") as f:
    f.write("\n".join(all_lines))

print("\n".join(all_lines[-10:]))