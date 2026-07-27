// =============================================================================
// reader_fsm.v
//
// Reads N results back out of dual_port_ram and drives the outbound
// AXI-Stream master interface.
//
// Per-sample timing: 2 cycles (WAIT_READ -> READ), matching dual_port_ram's
// 1-cycle read latency exactly, with no extra register stage:
//   WAIT_READ (addr_a presented combinationally)
//     -> at the edge leaving WAIT_READ, dout_re_a becomes valid
//   READ (dout_re_a now stable -> m_axis_tvalid asserted, wait for tready)
//     -> on handshake, either next address (WAIT_READ) or done (IDLE)
// =============================================================================
module reader_fsm #(
    parameter N      = 64,
    parameter ADDR_W = 6
)(
    input  wire clk,
    input  wire rst_n,

    input  wire start_read,       // 1-cycle pulse: begin reading a frame
    output wire done_read,        // combinational pulse: last sample handshaked

    // AXI-Stream master
    output wire        m_axis_tvalid,
    input  wire        m_axis_tready,
    output wire [31:0] m_axis_tdata,
    output wire        m_axis_tlast,

    // dual_port_ram port A (combinational - no extra register stage)
    output wire [ADDR_W-1:0]     addr_a,      // read-only: we_a tied 0 by top
    input  wire signed [15:0]    dout_re_a,
    input  wire signed [15:0]    dout_im_a
);

    localparam IDLE      = 2'd0;
    localparam WAIT_READ = 2'd1;
    localparam READ      = 2'd2;

    reg [1:0]        state, next_state;
    reg [ADDR_W-1:0] rd_cnt;

    wire hs = m_axis_tvalid && m_axis_tready;

    // Bit-reversed addressing: results land at the bit-reversed RAM
    // location of the natural frequency index (see calc_fsm/original
    // fft_controller comments for why). rd_cnt counts bins 0..N-1 in
    // natural order; the RAM address we actually fetch is its reverse.
    function [ADDR_W-1:0] bitrev;
        input [ADDR_W-1:0] x;
        integer i;
        begin
            for (i = 0; i < ADDR_W; i = i + 1)
                bitrev[i] = x[ADDR_W-1-i];
        end
    endfunction

    assign addr_a        = bitrev(rd_cnt);
    assign m_axis_tvalid = (state == READ);
    assign m_axis_tdata  = {dout_re_a, dout_im_a};              // stable throughout READ
    assign m_axis_tlast  = (state == READ) && (rd_cnt == N-1);
    assign done_read     = (state == READ) && hs && (rd_cnt == N-1);

    always @(*) begin
        next_state = state;
        case (state)
            IDLE:      next_state = start_read ? WAIT_READ : IDLE;
            WAIT_READ: next_state = READ;              // always exactly 1 cycle
            READ:      next_state = hs ? ((rd_cnt == N-1) ? IDLE : WAIT_READ)
                                        : READ;
            default:   next_state = IDLE;
        endcase
    end

    always @(posedge clk) begin
        if (!rst_n) state <= IDLE;
        else        state <= next_state;
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            rd_cnt <= {ADDR_W{1'b0}};
        end else begin
            case (state)
                IDLE: if (start_read) rd_cnt <= {ADDR_W{1'b0}};
                READ: if (hs && (rd_cnt != N-1)) rd_cnt <= rd_cnt + 1'b1;
                default: begin end
            endcase
        end
    end

endmodule