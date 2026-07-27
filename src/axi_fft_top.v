// =============================================================================
// axi_fft_top.v
//
// Sequences Loader -> Calculation -> Reader, each phase exclusively owning
// dual_port_ram (Loader/Reader time-share port A; Calculation uses A+B).
// The mux itself is a pure combinational select on the phase register - it
// adds no extra latency to the address/data path, unlike the old design.
//
// Cycle cost (see loader_fsm/reader_fsm/calc_fsm headers for the per-phase
// derivation):
//   load  = 2*N
//   calc  = 4*(N/2)*log2(N)
//   read  = 2*N
//   total = 4N + 2N*log2(N)
// For N=64 that's 4*64 + 2*64*6 = 256 + 768 = 1024 cycles, versus 1475 for
// the single-FSM version - the register-doubling was ~30% pure overhead.
// =============================================================================
module axi_fft_top #(
    parameter N       = 64,
    parameter ADDR_W  = 6,
    parameter STAGES  = 6
)(
    input  wire clk,
    input  wire rst_n,

    // Optional external hop trigger (e.g. from an STFT ring buffer). If you
    // just want free-running back-to-back frames, tie frame_trigger = 1'b1.
    input  wire frame_trigger,

    input  wire        s_axis_tvalid,
    output wire        s_axis_tready,
    input  wire signed [15:0] s_axis_tdata,

    output wire        m_axis_tvalid,
    input  wire        m_axis_tready,
    output wire [31:0] m_axis_tdata,
    output wire        m_axis_tlast
);

    // -------------------------------------------------------------------
    // Phase sequencer
    // -------------------------------------------------------------------
    localparam P_IDLE = 2'd0, P_LOAD = 2'd1, P_CALC = 2'd2, P_READ = 2'd3;
    reg [1:0] phase, next_phase;

    wire start_write, done_write;
    wire start_calculate, done_calculate;
    wire start_read, done_read;

    always @(*) begin
        next_phase = phase;
        case (phase)
            P_IDLE: next_phase = frame_trigger ? P_LOAD : P_IDLE;
            P_LOAD: next_phase = done_write     ? P_CALC : P_LOAD;
            P_CALC: next_phase = done_calculate ? P_READ : P_CALC;
            P_READ: next_phase = done_read      ? P_IDLE : P_READ;
            default: next_phase = P_IDLE;
        endcase
    end

    always @(posedge clk) begin
        if (!rst_n) phase <= P_IDLE;
        else        phase <= next_phase;
    end

    // 1-cycle start pulses, generated on phase entry
    assign start_write     = (phase == P_IDLE) && frame_trigger;
    assign start_calculate = (phase == P_LOAD) && done_write;
    assign start_read      = (phase == P_CALC) && done_calculate;

    // -------------------------------------------------------------------
    // Shared RAM
    // -------------------------------------------------------------------
    wire we_a, we_b;
    wire [ADDR_W-1:0] addr_a, addr_b;
    wire signed [15:0] din_re_a, din_im_a, din_re_b, din_im_b;
    wire signed [15:0] dout_re_a, dout_im_a, dout_re_b, dout_im_b;

    dual_port_ram #(.DATA_W(16), .ADDR_W(ADDR_W)) u_ram (
        .clk(clk),
        .we_a(we_a), .addr_a(addr_a), .din_re_a(din_re_a), .din_im_a(din_im_a),
        .dout_re_a(dout_re_a), .dout_im_a(dout_im_a),
        .we_b(we_b), .addr_b(addr_b), .din_re_b(din_re_b), .din_im_b(din_im_b),
        .dout_re_b(dout_re_b), .dout_im_b(dout_im_b)
    );

    // -------------------------------------------------------------------
    // Loader / Reader / Calc - each drives its own port A/B signals;
    // exactly one is "owned" at a time per `phase`.
    // -------------------------------------------------------------------
    wire ld_we_a; wire [ADDR_W-1:0] ld_addr_a; wire signed [15:0] ld_din_re_a;
    loader_fsm #(.N(N), .ADDR_W(ADDR_W)) u_loader (
        .clk(clk), .rst_n(rst_n),
        .start_write(start_write), .done_write(done_write),
        .s_axis_tvalid(s_axis_tvalid), .s_axis_tready(s_axis_tready),
        .s_axis_tdata(s_axis_tdata),
        .we_a(ld_we_a), .addr_a(ld_addr_a), .din_re_a(ld_din_re_a)
    );

    wire [ADDR_W-1:0] rd_addr_a;
    reader_fsm #(.N(N), .ADDR_W(ADDR_W)) u_reader (
        .clk(clk), .rst_n(rst_n),
        .start_read(start_read), .done_read(done_read),
        .m_axis_tvalid(m_axis_tvalid), .m_axis_tready(m_axis_tready),
        .m_axis_tdata(m_axis_tdata), .m_axis_tlast(m_axis_tlast),
        .addr_a(rd_addr_a), .dout_re_a(dout_re_a), .dout_im_a(dout_im_a)
    );

    wire calc_we_a, calc_we_b;
    wire [ADDR_W-1:0] calc_addr_a, calc_addr_b;
    wire signed [15:0] calc_din_re_a, calc_din_im_a, calc_din_re_b, calc_din_im_b;
    calc_fsm #(.STAGES(STAGES), .N(N), .ADDR_W(ADDR_W)) u_calc (
        .clk(clk), .rst_n(rst_n),
        .start_calculate(start_calculate), .done_calculate(done_calculate),
        .we_a(calc_we_a), .addr_a(calc_addr_a),
        .din_re_a(calc_din_re_a), .din_im_a(calc_din_im_a),
        .dout_re_a(dout_re_a), .dout_im_a(dout_im_a),
        .we_b(calc_we_b), .addr_b(calc_addr_b),
        .din_re_b(calc_din_re_b), .din_im_b(calc_din_im_b),
        .dout_re_b(dout_re_b), .dout_im_b(dout_im_b)
    );

    // -------------------------------------------------------------------
    // Port mux - pure combinational select on `phase`, no added latency.
    // Port A is time-shared between Loader/Reader/Calc; port B is Calc-only.
    // -------------------------------------------------------------------
    assign we_a      = (phase == P_LOAD) ? ld_we_a   :
                        (phase == P_CALC) ? calc_we_a : 1'b0;
    assign addr_a    = (phase == P_LOAD) ? ld_addr_a  :
                        (phase == P_CALC) ? calc_addr_a :
                        (phase == P_READ) ? rd_addr_a  : {ADDR_W{1'b0}};
    assign din_re_a  = (phase == P_LOAD) ? ld_din_re_a : calc_din_re_a;
    assign din_im_a  = (phase == P_CALC) ? calc_din_im_a : 16'sd0;

    assign we_b      = (phase == P_CALC) ? calc_we_b : 1'b0;
    assign addr_b    = (phase == P_CALC) ? calc_addr_b : {ADDR_W{1'b0}};
    assign din_re_b  = calc_din_re_b;
    assign din_im_b  = calc_din_im_b;

endmodule