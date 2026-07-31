def to_q15(x_float):
    """float in [-1,1) -> Q1.15 signed int16"""
    val = int(round(x_float * 32768))
    return max(-32768, min(32767, val))

def from_q15(x_int):
    return x_int / 32768.0

rom_hamming = [2621, 2696, 2920, 3291, 3805, 4457, 5241, 6148, 7170, 8297,
               9517, 10818, 12188, 13612, 15077, 16568, 18071, 19569, 21049,
               22495, 23894, 25231, 26494, 27668, 28744, 29710, 30557, 31275,
               31859, 32302, 32600, 32749, 32749, 32600, 32302, 31859, 31275,
               30557, 29710, 28744, 27668, 26494, 25231, 23894, 22495, 21049,
               19569, 18071, 16568, 15077, 13612, 12188, 10818, 9517, 8297,
               7170, 6148, 5241, 4457, 3805, 3291, 2920, 2696, 2621]

def apply_window(samples_q15):
    out = []
    for x, w in zip(samples_q15, rom_hamming):
        prod = x * w                  # Q1.15 * Q1.15 = Q2.30
        out.append(prod >> 15)        # rescale back to Q1.15, truncating (matches >>> 15 in RTL)
    print(f"This is the hamming table {out}")
    return out

def bitrev(x, bits):
    result = 0
    for i in range(bits):
        result = (result << 1) | (x & 1)
        x >>= 1
    return result

import math
import numpy as np 
def make_twiddle_table(max_size=64):
    """table[size][k] = (cos, sin) for exp(-j*2*pi*k/size), Q1.15, one table per size"""
    table = {}
    for size in [2, 4, 8, 16, 32, 64]:
        entries = []
        for k in range(size // 2):
            angle = -2 * math.pi * k / size
            entries.append((to_q15(math.cos(angle)), to_q15(math.sin(angle))))
        table[size] = entries
    
    return table

def fft_64(samples_q15, twiddle_table):
    N = 64
    stages = 6
    re = list(samples_q15)
    im = [0] * N

    for stage in range(1, stages + 1):
        size = 1 << stage
        half = size // 2
        num_groups = N // size
        for g in range(num_groups):
            for k in range(half):
                addr_a_nat = g * size + k
                addr_b_nat = addr_a_nat + half
                addr_a = bitrev(addr_a_nat, 6)
                addr_b = bitrev(addr_b_nat, 6)

                tw_re, tw_im = twiddle_table[size][k]
                a_re, a_im = re[addr_a], im[addr_a]
                b_re, b_im = re[addr_b], im[addr_b]

                out_a_re, out_a_im, out_b_re, out_b_im = butterfly(
                    a_re, a_im, b_re, b_im, tw_re, tw_im)

                re[addr_a], im[addr_a] = out_a_re, out_a_im
                re[addr_b], im[addr_b] = out_b_re, out_b_im 
        print(f"The real part of stage {stage}: {re}")
        print(f"The imagine part of stage {stage}: {im}")

    # final read-out uses bitrev addressing too, matching reader_fsm
    out_re = [re[bitrev(i, 6)] for i in range(N)]
    out_im = [im[bitrev(i, 6)] for i in range(N)]
    return out_re, out_im


log2_lut = [0, 89, 174, 255, 330, 401, 469, 534, 599, 660, 717, 773,
            827, 879, 929, 977, 1024]

def log2_fixed(cap_prod):  # cap_prod: unsigned 17-bit, Q2.15
    if cap_prod == 0:
        cap_prod = 1  # epsilon floor, matching SUM state's clamp

    # priority encoder: leading zero count in 17 bits
    lz = 0
    for bit in range(16, -1, -1):
        if (cap_prod >> bit) & 1:
            lz = 16 - bit
            break

    int_part = 16 - lz -15
    norm_cap = (cap_prod << lz) & 0x1FFFF
    lut_idx = (norm_cap >> 12) & 0xF
    lut_rem = norm_cap & 0xFFF

    lut_y0 = log2_lut[lut_idx]
    lut_delta = log2_lut[lut_idx + 1] - lut_y0
    frac_part = lut_y0 + ((lut_delta * lut_rem) >> 12)

    return (int_part << 10) | frac_part  # Q5.10, matches m_axis_tdata packing

def magnitude_log2(re, im):
    print(f"Original cap product {re*re + im*im}")
    re_sq = (re * re) >> 15
    im_sq = (im * im) >> 15
    cap_prod = re_sq + im_sq
    print(f"Cap product {cap_prod}")
    log_prod = log2_fixed(cap_prod)
    print(f"Log product {log_prod}")
    return log_prod

def full_pipeline(samples_float):
    samples_q15 = [to_q15(s) for s in samples_float]
    windowed = apply_window(samples_q15)
    twiddle_table = make_twiddle_table()
    out_re, out_im = fft_64(windowed, twiddle_table)
    bins = [magnitude_log2(out_re[i], out_im[i]) for i in range(33)]
    return bins 

def butterfly(a_re, a_im, b_re, b_im, tw_re, tw_im):
    # complex multiply: B * twiddle, Q1.15 x Q1.15 = Q2.30, truncate back to Q1.15
    bw_re = ((b_re * tw_re) >> 15) - ((b_im * tw_im) >> 15)
    bw_im = ((b_re * tw_im) >> 15) + ((b_im * tw_re) >> 15)

    sum_re = a_re + bw_re
    sum_im = a_im + bw_im
    diff_re = a_re - bw_re
    diff_im = a_im - bw_im

    # scaled FFT: shift right by 1 every stage, matching butterfly.v
    out_a_re = sum_re >> 1
    out_a_im = sum_im >> 1
    out_b_re = diff_re >> 1
    out_b_im = diff_im >> 1
    return out_a_re, out_a_im, out_b_re, out_b_im

def compute_fft_64_log(signal: np.ndarray, eps: float = 1e-12) -> dict:
    """
    Computes 64-point FFT magnitude on both linear and log scales.
    
    Returns:
        - magnitude: Linear magnitude spectrum |X[k]|
        - log_magnitude: log10(|X[k]|)
        - db_scale: Magnitude in decibels (20 * log10(|X[k]|))
    """
    # 1. 64-point FFT
    fft_output = np.fft.fft(signal, n=64)
    
    # 2. Linear magnitude
    magnitude = np.abs(fft_output)
    
    # 3. Log scale (Base 10)
    log_magnitude = np.log2(magnitude + eps)
    
    # 4. Decibel (dB) scale
    db_scale = 20 * np.log2(np.maximum(magnitude, eps))
    
    return {
        "magnitude": magnitude,
        "log_magnitude": log_magnitude,
        "db_scale": db_scale
    }
print("--------------------------")
print("My pipeline")
print(full_pipeline([(i*256 + i+1)/32768 for i in range(0,128,2)]))
print("--------------------------")
print("The original function")
print(64*compute_fft_64_log([(i*256 + i+1)/32768  for i in range(0,128,2)])['log_magnitude'][0:32]) 

