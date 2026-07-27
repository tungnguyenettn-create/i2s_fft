// =============================================================================
// butterfly.v  –  Radix-2 DIT butterfly, Q1.15 fixed-point, combinational
//
// A_out = A + W * B
// B_out = A - W * B
//
// Q1.15 multiply: 16b × 16b → 32b product; keep bits [30:15] (drop sign dup + LSBs)
// Guarded add/sub with 17-bit headroom, then round back to 16b by dropping LSB.
// =============================================================================
module butterfly #(
    parameter DATA_W = 16
)(
    input  wire signed [DATA_W-1:0] A_re,
    input  wire signed [DATA_W-1:0] A_im,
    input  wire signed [DATA_W-1:0] B_re,
    input  wire signed [DATA_W-1:0] B_im,
    input  wire signed [DATA_W-1:0] W_re,
    input  wire signed [DATA_W-1:0] W_im,

    output wire signed [DATA_W-1:0] A_out_re,
    output wire signed [DATA_W-1:0] A_out_im,
    output wire signed [DATA_W-1:0] B_out_re,
    output wire signed [DATA_W-1:0] B_out_im
);
    // --- Complex multiply  W * B  (Q1.15 × Q1.15 → Q1.15) ---
    wire signed [2*DATA_W-1:0] BW_re_full = (B_re * W_re) - (B_im * W_im);
    wire signed [2*DATA_W-1:0] BW_im_full = (B_re * W_im) + (B_im * W_re);

    // Round to Q1.15: product is Q2.30; take bits [30:15] → Q1.15
    wire signed [DATA_W-1:0] BW_re = BW_re_full[2*DATA_W-2 : DATA_W-1];
    wire signed [DATA_W-1:0] BW_im = BW_im_full[2*DATA_W-2 : DATA_W-1];

    // --- Butterfly add/sub with 1-bit overflow guard then /2 ---
    wire signed [DATA_W:0] sum_re  = $signed({A_re[DATA_W-1], A_re}) + $signed({BW_re[DATA_W-1], BW_re});
    wire signed [DATA_W:0] sum_im  = $signed({A_im[DATA_W-1], A_im}) + $signed({BW_im[DATA_W-1], BW_im});
    wire signed [DATA_W:0] diff_re = $signed({A_re[DATA_W-1], A_re}) - $signed({BW_re[DATA_W-1], BW_re});
    wire signed [DATA_W:0] diff_im = $signed({A_im[DATA_W-1], A_im}) - $signed({BW_im[DATA_W-1], BW_im});

    // Arithmetic right-shift by 1 (divide by 2 to prevent overflow accumulation)
    assign A_out_re = sum_re [DATA_W:1];
    assign A_out_im = sum_im [DATA_W:1];
    assign B_out_re = diff_re[DATA_W:1];
    assign B_out_im = diff_im[DATA_W:1];

endmodule