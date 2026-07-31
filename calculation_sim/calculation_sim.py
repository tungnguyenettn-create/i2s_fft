import math
import random
import scipy.stats as stats
import numpy as np


def to_q15(x_float):
    """float in [-1,1) -> Q1.15 signed int16"""
    val = int(round(x_float * 32768))
    return max(-32768, min(32767, val))


def from_q15(x_int):
    return x_int / 32768.0


rom_hamming = [
    2621, 2696, 2920, 3291, 3805, 4457, 5241, 6148, 7170, 8297,
    9517, 10818, 12188, 13612, 15077, 16568, 18071, 19569, 21049,
    22495, 23894, 25231, 26494, 27668, 28744, 29710, 30557, 31275,
    31859, 32302, 32600, 32749, 32749, 32600, 32302, 31859, 31275,
    30557, 29710, 28744, 27668, 26494, 25231, 23894, 22495, 21049,
    19569, 18071, 16568, 15077, 13612, 12188, 10818, 9517, 8297,
    7170, 6148, 5241, 4457, 3805, 3291, 2920, 2696, 2621,
]


def apply_window(samples_q15, trace_list=None):
    out = []
    for x, w in zip(samples_q15, rom_hamming):
        prod = x * w  # Q1.15 * Q1.15 = Q2.30
        out.append(prod >> 15)  # rescale back to Q1.15
    if trace_list is not None:
        trace_list.append("--- STEP 1: Windowed Samples (Q1.15) ---")
        trace_list.append(f"{out}\n")
    return out


def bitrev(x, bits):
    result = 0
    for _ in range(bits):
        result = (result << 1) | (x & 1)
        x >>= 1
    return result


def make_twiddle_table(max_size=64):
    """table[size][k] = (cos, sin) for exp(-j*2*pi*k/size), Q1.15"""
    table = {}
    for size in [2, 4, 8, 16, 32, 64]:
        entries = []
        for k in range(size // 2):
            angle = -2 * math.pi * k / size
            entries.append((to_q15(math.cos(angle)), to_q15(math.sin(angle))))
        table[size] = entries
    return table


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


def fft_64(samples_q15, twiddle_table, trace_list=None):
    N = 64
    stages = 6
    re = list(samples_q15)
    im = [0] * N

    if trace_list is not None:
        trace_list.append("--- STEP 2: FFT Stages ---")

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
                    a_re, a_im, b_re, b_im, tw_re, tw_im
                )

                re[addr_a], im[addr_a] = out_a_re, out_a_im
                re[addr_b], im[addr_b] = out_b_re, out_b_im

        if trace_list is not None:
            max_re = max(abs(x) for x in re)
            max_im = max(abs(x) for x in im)
            trace_list.append(
                f"Stage {stage} Max Abs Real: {max_re} | Max Abs Imag: {max_im}"
            )
            trace_list.append(f"  Real: {re}")
            trace_list.append(f"  Imag: {im}\n")

    out_re = [re[bitrev(i, 6)] for i in range(N)]
    out_im = [im[bitrev(i, 6)] for i in range(N)]
    return out_re, out_im


log2_lut = [
    0, 89, 174, 255, 330, 401, 469, 534, 599, 660, 717, 773, 827, 879,
    929, 977, 1024,
]


def log2_q230(cap_prod):
    clamped = False
    if cap_prod == 0:
        cap_prod = 1  # epsilon floor
        clamped = True

    p = cap_prod.bit_length() - 1
    int_part = p - 30
    shift = 31 - p
    norm_cap = (cap_prod << shift) & 0xFFFFFFFF

    lut_idx = (norm_cap >> 27) & 0xF
    lut_rem = (norm_cap >> 15) & 0xFFF

    lut_y0 = log2_lut[lut_idx]
    lut_delta = log2_lut[lut_idx + 1] - lut_y0
    frac_part = lut_y0 + ((lut_delta * lut_rem) >> 12)

    combined = int_part + frac_part / 1024.0
    return int_part, frac_part, combined, clamped, cap_prod



def full_pipeline(samples_float, return_trace=True):
    trace_list = []

    # Input Conversion
    samples_q15 = [to_q15(s) for s in samples_float]
    if return_trace:
        trace_list.append("--- STEP 0: Raw Input vs Q1.15 Input ---")
        trace_list.append(f"Raw Input Floats: {samples_float}")
        trace_list.append(f"Q1.15 Converted : {samples_q15}\n")

    # Windowing
    windowed = apply_window(samples_q15, trace_list if return_trace else None)

    # FFT
    twiddle_table = make_twiddle_table()
    out_re, out_im = fft_64(
        windowed, twiddle_table, trace_list if return_trace else None
    )

    # Magnitude & Log Computation
    bins = []
    if return_trace:
        trace_list.append("--- STEP 3: Magnitude & Log2 Computation ---")

    for i in range(33):
        re_sq = out_re[i] * out_re[i]
        im_sq = out_im[i] * out_im[i]
        cap_prod = re_sq + im_sq
        _, _, combined, clamped, _ = log2_q230(cap_prod)
        bins.append(combined)

        if return_trace:
            clamp_str = " (CLAMPED TO 1)" if clamped else ""
            trace_list.append(
                f"Bin {i:02d}: Re={out_re[i]:6d}, Im={out_im[i]:6d} | "
                f"cap_prod={cap_prod:10d}{clamp_str} -> log2={combined:.6f}"
            )

    trace_string = "\n".join(trace_list) if return_trace else ""
    return bins, trace_string


def compute_fft_64_log(signal: np.ndarray, eps: float = 1e-12) -> dict:
    # Hamming window
    window = np.hamming(64)

    # Apply window
    windowed_signal = signal[:64] * window

    # FFT
    fft_output = np.fft.fft(windowed_signal, n=64)

    # Magnitude
    magnitude = np.abs(fft_output)

    # Log magnitude
    log_magnitude = np.log2(magnitude + eps)

    # dB scale
    db_scale = 20 * np.log2(np.maximum(magnitude, eps))

    return {
        "window": window,
        "windowed_signal": windowed_signal,
        "fft_output": fft_output,
        "magnitude": magnitude,
        "log_magnitude": log_magnitude,
        "db_scale": db_scale,
    }

def check_numerical(output_file="worst_10_scores.txt"):
    avg_stat = 0
    results = []

    print("Running 1,000 iterations...")
    for i in range(1000):
        random_string = [1-0.1*random.random() for _ in range(64)]
        my_ans, trace_logs = full_pipeline(random_string, return_trace=True)
        ori_ans = compute_fft_64_log(random_string)["log_magnitude"][0:33]

        score = stats.pearsonr(my_ans, ori_ans).statistic
        avg_stat += score

        results.append(
            {
                "iteration": i,
                "string": random_string,
                "score": score,
                "my_ans": my_ans,
                "ori_ans": ori_ans,
                "trace_logs": trace_logs,
            }
        )

    avg_stat = avg_stat / 1000
    print("-" * 64)
    print(f"Average Pearson Correlation across 1000 runs: {avg_stat:.6f}")

    # Extract 10 lowest scoring iterations
    lowest_10 = sorted(results, key=lambda x: x["score"])[:10]

    # Save details and full trace logs to text file
    with open(output_file, "w") as f:
        f.write("========================================================\n")
        f.write("=== 10 LOWEST PEARSON CORRELATION SCORES & DETAILED TRACES ===\n")
        f.write("========================================================\n")
        f.write(f"Overall Average Score (1000 runs): {avg_stat:.6f}\n\n")

        for rank, item in enumerate(lowest_10, 1):
            f.write("=" * 70 + "\n")
            f.write(
                f"RANK #{rank} | Iteration: {item['iteration']} | Pearson Score: {item['score']:.6f}\n"
            )
            f.write("=" * 70 + "\n\n")

            f.write("My Pipeline Bin Results (33 bins):\n")
            f.write(f"{item['my_ans']}\n\n")

            f.write("Original Floating-Point Reference (33 bins):\n")
            f.write(f"{item['ori_ans'].tolist()}\n\n")

            f.write("DETAILED STEP-BY-STEP TRACE LOG:\n")
            f.write("-" * 50 + "\n")
            f.write(item["trace_logs"])
            f.write("\n\n" + "#" * 70 + "\n\n")

    print(f"Successfully saved worst 10 step-by-step traces to '{output_file}'.")


if __name__ == "__main__":
    check_numerical()