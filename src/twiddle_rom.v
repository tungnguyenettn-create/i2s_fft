// =============================================================================
// twiddle_rom.v
// FFT Twiddle Factor ROM - Q1.15 Fixed-Point Format
//
// W_N^k = e^(-j*2*pi*k/N) = cos(2*pi*k/N) - j*sin(2*pi*k/N)
// Q1.15: 1 sign bit + 15 fractional bits, int16_t range [-32768, 32767]
//
// Supported FFT sizes : N = 2, 4, 8, 16, 32, 64
// Address map (flat ROM, 63 entries total):
//
//   N= 2 : base_addr =  0, entries =  1  (addr  0)
//   N= 4 : base_addr =  1, entries =  2  (addr  1 ..  2)
//   N= 8 : base_addr =  3, entries =  4  (addr  3 ..  6)
//   N=16 : base_addr =  7, entries =  8  (addr  7 .. 14)
//   N=32 : base_addr = 15, entries = 16  (addr 15 .. 30)
//   N=64 : base_addr = 31, entries = 32  (addr 31 .. 62)
//
// Ports:
//   clk       - clock (rising-edge registered output)
//   rst_n     - active-low synchronous reset
//   fft_size  - FFT size selector: 2,4,8,16,32,64  (must be power-of-2)
//   k         - twiddle index 0 .. (fft_size/2 - 1)
//   valid_in  - pulse high for one cycle to latch a new request
//   tw_re     - Q1.15 real part  (registered, available next cycle)
//   tw_im     - Q1.15 imaginary part (registered, available next cycle)
//   valid_out - high the cycle tw_re/tw_im are valid
// =============================================================================

module twiddle_rom #(
    parameter DATA_W = 16,   // Q1.15 word width
    parameter ADDR_W = 6     // ceil(log2(63)) = 6
)(
    input  wire                  clk,
    input  wire                  rst_n,

    // Request interface
    input  wire [6:0]            fft_size,   // 2,4,8,16,32,64
    input  wire [4:0]            k,          // twiddle index 0..31
    input  wire                  valid_in,

    // Response (1 cycle latency)
    output reg  signed [DATA_W-1:0] tw_re,
    output reg  signed [DATA_W-1:0] tw_im,
    output reg                      valid_out
);

    // -------------------------------------------------------------------------
    // ROM storage: 63 entries × 32-bit word {re[15:0], im[15:0]}
    // -------------------------------------------------------------------------
    reg signed [DATA_W-1:0] rom_re [0:62];
    reg signed [DATA_W-1:0] rom_im [0:62];

    initial begin
        // --- N=2 : base 0 ---
        rom_re[ 0] =  16'sd32767; rom_im[ 0] =  16'sd0;

        // --- N=4 : base 1 ---
        rom_re[ 1] =  16'sd32767; rom_im[ 1] =  16'sd0;
        rom_re[ 2] =  16'sd0;     rom_im[ 2] = -16'sd32768;

        // --- N=8 : base 3 ---
        rom_re[ 3] =  16'sd32767; rom_im[ 3] =  16'sd0;
        rom_re[ 4] =  16'sd23170; rom_im[ 4] = -16'sd23170;
        rom_re[ 5] =  16'sd0;     rom_im[ 5] = -16'sd32768;
        rom_re[ 6] = -16'sd23170; rom_im[ 6] = -16'sd23170;

        // --- N=16 : base 7 ---
        rom_re[ 7] =  16'sd32767; rom_im[ 7] =  16'sd0;
        rom_re[ 8] =  16'sd30274; rom_im[ 8] = -16'sd12540;
        rom_re[ 9] =  16'sd23170; rom_im[ 9] = -16'sd23170;
        rom_re[10] =  16'sd12540; rom_im[10] = -16'sd30274;
        rom_re[11] =  16'sd0;     rom_im[11] = -16'sd32768;
        rom_re[12] = -16'sd12540; rom_im[12] = -16'sd30274;
        rom_re[13] = -16'sd23170; rom_im[13] = -16'sd23170;
        rom_re[14] = -16'sd30274; rom_im[14] = -16'sd12540;

        // --- N=32 : base 15 ---
        rom_re[15] =  16'sd32767; rom_im[15] =  16'sd0;
        rom_re[16] =  16'sd32138; rom_im[16] = -16'sd6393;
        rom_re[17] =  16'sd30274; rom_im[17] = -16'sd12540;
        rom_re[18] =  16'sd27246; rom_im[18] = -16'sd18205;
        rom_re[19] =  16'sd23170; rom_im[19] = -16'sd23170;
        rom_re[20] =  16'sd18205; rom_im[20] = -16'sd27246;
        rom_re[21] =  16'sd12540; rom_im[21] = -16'sd30274;
        rom_re[22] =  16'sd6393;  rom_im[22] = -16'sd32138;
        rom_re[23] =  16'sd0;     rom_im[23] = -16'sd32768;
        rom_re[24] = -16'sd6393;  rom_im[24] = -16'sd32138;
        rom_re[25] = -16'sd12540; rom_im[25] = -16'sd30274;
        rom_re[26] = -16'sd18205; rom_im[26] = -16'sd27246;
        rom_re[27] = -16'sd23170; rom_im[27] = -16'sd23170;
        rom_re[28] = -16'sd27246; rom_im[28] = -16'sd18205;
        rom_re[29] = -16'sd30274; rom_im[29] = -16'sd12540;
        rom_re[30] = -16'sd32138; rom_im[30] = -16'sd6393;

        // --- N=64 : base 31 ---
        rom_re[31] =  16'sd32767; rom_im[31] =  16'sd0;
        rom_re[32] =  16'sd32610; rom_im[32] = -16'sd3212;
        rom_re[33] =  16'sd32138; rom_im[33] = -16'sd6393;
        rom_re[34] =  16'sd31357; rom_im[34] = -16'sd9512;
        rom_re[35] =  16'sd30274; rom_im[35] = -16'sd12540;
        rom_re[36] =  16'sd28899; rom_im[36] = -16'sd15447;
        rom_re[37] =  16'sd27246; rom_im[37] = -16'sd18205;
        rom_re[38] =  16'sd25330; rom_im[38] = -16'sd20788;
        rom_re[39] =  16'sd23170; rom_im[39] = -16'sd23170;
        rom_re[40] =  16'sd20788; rom_im[40] = -16'sd25330;
        rom_re[41] =  16'sd18205; rom_im[41] = -16'sd27246;
        rom_re[42] =  16'sd15447; rom_im[42] = -16'sd28899;
        rom_re[43] =  16'sd12540; rom_im[43] = -16'sd30274;
        rom_re[44] =  16'sd9512;  rom_im[44] = -16'sd31357;
        rom_re[45] =  16'sd6393;  rom_im[45] = -16'sd32138;
        rom_re[46] =  16'sd3212;  rom_im[46] = -16'sd32610;
        rom_re[47] =  16'sd0;     rom_im[47] = -16'sd32768;
        rom_re[48] = -16'sd3212;  rom_im[48] = -16'sd32610;
        rom_re[49] = -16'sd6393;  rom_im[49] = -16'sd32138;
        rom_re[50] = -16'sd9512;  rom_im[50] = -16'sd31357;
        rom_re[51] = -16'sd12540; rom_im[51] = -16'sd30274;
        rom_re[52] = -16'sd15447; rom_im[52] = -16'sd28899;
        rom_re[53] = -16'sd18205; rom_im[53] = -16'sd27246;
        rom_re[54] = -16'sd20788; rom_im[54] = -16'sd25330;
        rom_re[55] = -16'sd23170; rom_im[55] = -16'sd23170;
        rom_re[56] = -16'sd25330; rom_im[56] = -16'sd20788;
        rom_re[57] = -16'sd27246; rom_im[57] = -16'sd18205;
        rom_re[58] = -16'sd28899; rom_im[58] = -16'sd15447;
        rom_re[59] = -16'sd30274; rom_im[59] = -16'sd12540;
        rom_re[60] = -16'sd31357; rom_im[60] = -16'sd9512;
        rom_re[61] = -16'sd32138; rom_im[61] = -16'sd6393;
        rom_re[62] = -16'sd32610; rom_im[62] = -16'sd3212;
    end

    // -------------------------------------------------------------------------
    // Base-address lookup  (combinational)
    //   Formula: base = (N/2) - 1
    //   N= 2 -> base=  0
    //   N= 4 -> base=  1
    //   N= 8 -> base=  3
    //   N=16 -> base=  7
    //   N=32 -> base= 15
    //   N=64 -> base= 31
    // -------------------------------------------------------------------------
    reg [ADDR_W-1:0] base_addr;

    always @(*) begin
        case (fft_size)
            7'd2  : base_addr = 6'd0;
            7'd4  : base_addr = 6'd1;
            7'd8  : base_addr = 6'd3;
            7'd16 : base_addr = 6'd7;
            7'd32 : base_addr = 6'd15;
            7'd64 : base_addr = 6'd31;
            default: base_addr = 6'd0;  // safe default
        endcase
    end

    // -------------------------------------------------------------------------
    // Flat ROM address  =  base_addr + k
    // -------------------------------------------------------------------------
    wire [ADDR_W-1:0] rom_addr = base_addr + {{1{1'b0}}, k};

    // -------------------------------------------------------------------------
    // Registered output  (single-cycle latency)
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            tw_re     <= {DATA_W{1'b0}};
            tw_im     <= {DATA_W{1'b0}};
            valid_out <= 1'b0;
        end else begin
            valid_out <= valid_in;
            if (valid_in) begin
                tw_re <= rom_re[rom_addr];
                tw_im <= rom_im[rom_addr];
            end
        end
    end

endmodule