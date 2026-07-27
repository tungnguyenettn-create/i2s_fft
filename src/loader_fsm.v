// =============================================================================
// loader_fsm.v
//
// Handles the inbound AXI-Stream handshake and writes samples into
// dual_port_ram, one address per sample, N samples total.
//
// Per-sample timing: 2 cycles (WAIT_WRITE -> WRITE), NOT 3 - because
// we_a/addr_a/din_re_a are driven COMBINATIONALLY from state + handshake,
// with no extra register stage in between. dual_port_ram itself only needs
// 1 cycle of write latency once we_a/addr/din are presented, so:
//   WAIT_WRITE (handshake happens, we_a/addr/din asserted combinationally)
//     -> at the edge leaving WAIT_WRITE, the RAM commits the write
//   WRITE (settle: we_a deasserts, wr_cnt advances, done_write checked)
//     -> back to WAIT_WRITE for the next sample
// =============================================================================
module loader_fsm #(
    parameter N      = 64,
    parameter ADDR_W = 6
)(
    input  wire clk,
    input  wire rst_n,

    input  wire start_write,      // 1-cycle pulse: begin loading a frame
    output wire done_write,       // combinational pulse: last sample committed

    // AXI-Stream slave
    input  wire                  s_axis_tvalid,
    output wire                  s_axis_tready,
    input  wire signed [15:0]    s_axis_tdata,

    // dual_port_ram port A (combinational - no extra register stage)
    output wire                  we_a,
    output wire [ADDR_W-1:0]     addr_a,
    output wire signed [15:0]    din_re_a
);

    localparam IDLE       = 2'd0;
    localparam WAIT_WRITE = 2'd1;
    localparam WRITE      = 2'd2;

    reg [1:0]        state, next_state;
    reg [ADDR_W-1:0] wr_cnt;

    wire hs = s_axis_tvalid && s_axis_tready;  // AXI handshake this cycle

    // -------------------------------------------------------------------
    // Combinational RAM-facing signals - directly reflect current state,
    // no register in the path from FSM decision to RAM input.
    // -------------------------------------------------------------------
    assign s_axis_tready = (state == WAIT_WRITE);
    assign we_a           = (state == WAIT_WRITE) && hs;
    assign addr_a         = wr_cnt;
    assign din_re_a       = s_axis_tdata;

    // done_write pulses combinationally the cycle the *last* sample's
    // handshake occurs (it will physically commit on the edge leaving
    // this cycle, exactly as with every other sample).
    assign done_write = (state == WAIT_WRITE) && hs && (wr_cnt == N-1);

    // -------------------------------------------------------------------
    // Next state
    // -------------------------------------------------------------------
    always @(*) begin
        next_state = state;
        case (state)
            IDLE:       next_state = start_write ? WAIT_WRITE : IDLE;
            WAIT_WRITE: next_state = hs ? WRITE : WAIT_WRITE;
            // wr_cnt has NOT been incremented yet this cycle (nonblocking),
            // so it still holds the address that was just written.
            WRITE:      next_state = (wr_cnt == N-1) ? IDLE : WAIT_WRITE;
            default:    next_state = IDLE;
        endcase
    end

    always @(posedge clk) begin
        if (!rst_n) state <= IDLE;
        else        state <= next_state;
    end

    // -------------------------------------------------------------------
    // wr_cnt bookkeeping
    // -------------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            wr_cnt <= {ADDR_W{1'b0}};
        end else begin
            case (state)
                IDLE: if (start_write) wr_cnt <= {ADDR_W{1'b0}};
                WAIT_WRITE: begin
                    // wr_cnt advances the cycle after a successful handshake
                    // (i.e. during WRITE), see below.
                end
                WRITE: begin
                    if (wr_cnt != N-1)
                        wr_cnt <= wr_cnt + 1'b1;
                    // if wr_cnt == N-1, we're heading back to IDLE anyway;
                    // IDLE's branch above resets wr_cnt on the next start_write.
                end
                default: begin end
            endcase
        end
    end

endmodule