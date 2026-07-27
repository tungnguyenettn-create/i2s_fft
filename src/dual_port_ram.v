// =============================================================================
// dual_port_ram.v  –  True dual-port RAM, 64 × 16-bit complex (re + im)
// Fixed bugs from original:
//   1. dout used undeclared 'ram[]' – corrected to ram_re / ram_im
//   2. Last always block wrote to dout_re_a instead of dout_re_b
// =============================================================================
module dual_port_ram #(
    parameter DATA_W = 16,
    parameter ADDR_W = 6    // 64 entries
)(
    input  wire                  clk,

    // Port A
    input  wire                  we_a,
    input  wire [ADDR_W-1:0]     addr_a,
    input  wire signed [DATA_W-1:0] din_re_a,
    input  wire signed [DATA_W-1:0] din_im_a,
    output reg  signed [DATA_W-1:0] dout_re_a,
    output reg  signed [DATA_W-1:0] dout_im_a,

    // Port B
    input  wire                  we_b,
    input  wire [ADDR_W-1:0]     addr_b,
    input  wire signed [DATA_W-1:0] din_re_b,
    input  wire signed [DATA_W-1:0] din_im_b,
    output reg  signed [DATA_W-1:0] dout_re_b,
    output reg  signed [DATA_W-1:0] dout_im_b
);
    localparam RAM_DEPTH = 1 << ADDR_W;

    reg signed [DATA_W-1:0] ram_re [0:RAM_DEPTH-1];
    reg signed [DATA_W-1:0] ram_im [0:RAM_DEPTH-1];

    // Port A – real
    always @(posedge clk) begin
        if (we_a) ram_re[addr_a] <= din_re_a;
        else dout_re_a <= ram_re[addr_a];
    end

    // Port A – imaginary
    always @(posedge clk) begin
        if (we_a) ram_im[addr_a] <= din_im_a;
        else dout_im_a <= ram_im[addr_a];
    end

    // Port B – real
    always @(posedge clk) begin
        if (we_b) ram_re[addr_b] <= din_re_b;
        else dout_re_b <= ram_re[addr_b];      // was incorrectly dout_re_a
    end

    // Port B – imagsinary
    always @(posedge clk) begin
        if (we_b) ram_im[addr_b] <= din_im_b;
        else dout_im_b <= ram_im[addr_b];
    end
    
endmodule