"""
Python model of the CORRECTED axi_output.v logic:
  - re, im are Q1.15 signed (range [-32768, 32767])
  - squared and summed directly at full Q2.30 width (cap_prod), no early
    truncation -- this is the fix for the underflow bug we found earlier
  - priority-encode the leading bit position p (0..31)
  - true exponent e = p - 30 (binary point sits after bit 30, since
    re/im's "ones place" is bit 15, and squaring doubles that to bit 30)
  - normalize so the leading 1 lands at bit 31, use the next 4 bits as
    a LUT index into log2(1.x), interpolate the remainder
  - pack as Q6.10 signed: int_part in [-30, 1], frac_part 10 bits
"""

log2_lut = [0, 89, 174, 255, 330, 401, 469, 534, 599, 660, 717, 773,
            827, 879, 929, 977, 1024]

def log2_q230(cap_prod):
    """
    cap_prod: unsigned int, up to 32 bits, representing re^2+im^2 in
              raw Q2.30 form (binary point after bit 30).
    Returns: (int_part, frac_part) matching Q6.10 signed packing,
             and also the combined float value for easy comparison.
    """
    if cap_prod == 0:
        cap_prod = 1  # epsilon floor, matches SUM state's clamp

    # --- Priority encoder: find position p of the highest set bit ---
    p = cap_prod.bit_length() - 1   # 0..31

    # --- True exponent: e = p - 30 (the fixed formula, off-by-one corrected) ---
    int_part = p - 30

    # --- Normalize: shift left so the leading bit lands at bit 31 ---
    shift = 31 - p
    norm_cap = (cap_prod << shift) & 0xFFFFFFFF   # keep to 32 bits

    # --- LUT index: top 4 bits below the implied leading 1 (bit 31) ---
    lut_idx = (norm_cap >> 27) & 0xF
    # --- Remainder: next 12 bits, used for linear interpolation ---
    lut_rem = (norm_cap >> 15) & 0xFFF

    lut_y0 = log2_lut[lut_idx]
    lut_delta = log2_lut[lut_idx + 1] - lut_y0
    frac_part = lut_y0 + ((lut_delta * lut_rem) >> 12)

    # combined value, for easy sanity-checking against math.log2()
    combined = int_part + frac_part / 1024.0

    return int_part, frac_part, combined


def magnitude_log2_q230(re, im):
    """re, im: signed Q1.15 ints. Returns (int_part, frac_part, combined_float)."""
    re_sq = re * re   # full Q2.30, no truncation
    im_sq = im * im
    cap_prod = re_sq + im_sq
    return log2_q230(cap_prod)


if __name__ == "__main__":
    import math

    print(f"{'re':>7} {'im':>7} | {'cap_prod':>12} | {'int_part':>8} {'frac':>5} | {'combined':>9} | {'true log2':>10} | {'err':>6}")

    test_cases = [
        (-32768, -32768),   # absolute max: should hit int_part=1 exactly
        (32767, 0),
        (100, 100),
        (11, -61),           # the "quiet bin" case from earlier -- used to underflow to 0
        (1, 0),
        (0, 1),
        (-1, 0),
    ]

    for re, im in test_cases:
        int_part, frac_part, combined = magnitude_log2_q230(re, im)
        true_val = re*re + im*im
        true_log2 = math.log2(true_val / (2**30)) if true_val > 0 else float('-inf')
        err = combined - true_log2 if true_val > 0 else float('nan')
        print(f"{re:7d} {im:7d} | {re*re+im*im:12d} | {int_part:8d} {frac_part:5d} | {combined:9.4f} | {true_log2:10.4f} | {err:6.4f}")