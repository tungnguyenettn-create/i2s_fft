// =============================================================================
// calc_fsm.v
//
// Serialized radix-2 DIT butterfly engine. Owns dual_port_ram ports A and B
// while active. 4 cycles per butterfly (READ_MEM -> LATENCY -> CALCULATE ->
// WRITE_MEM), not 5: index/stage advance is folded into WRITE_MEM instead of
// a separate UPDATE state, and we_a/we_b/addr/din are combinational
// functions of `state` - no extra register stage delaying them into the RAM.
// =============================================================================
module calc_fsm #(
    parameter STAGES  = 6,     // log2(N)
    parameter N        = 64,
    parameter ADDR_W  = 6
)(
    input  wire clk,
    input  wire rst_n,

    input  wire start_calculate,
    output wire done_calculate,   // combinational pulse on the terminal WRITE_MEM cycle

    // dual_port_ram port A
    output wire                  we_a,
    output wire [ADDR_W-1:0]     addr_a,
    output wire signed [15:0]    din_re_a,
    output wire signed [15:0]    din_im_a,
    input  wire signed [15:0]    dout_re_a,
    input  wire signed [15:0]    dout_im_a,

    // dual_port_ram port B
    output wire                  we_b,
    output wire [ADDR_W-1:0]     addr_b,
    output wire signed [15:0]    din_re_b,
    output wire signed [15:0]    din_im_b,
    input  wire signed [15:0]    dout_re_b,
    input  wire signed [15:0]    dout_im_b
);

    localparam IDLE      = 3'd0;
    localparam READ_MEM  = 3'd1;
    localparam LATENCY   = 3'd2;
    localparam CALCULATE = 3'd3;
    localparam WRITE_MEM = 3'd4;

    reg [2:0] state, next_state;

    // stage: 1..STAGES, index: 0..(N/2 - 1)
    localparam IDX_W = ADDR_W - 1;  // N/2 needs one fewer bit than N
    reg [2:0]        stage;
    reg [IDX_W-1:0]  index;

    localparam LAST_STAGE = STAGES;
    localparam LAST_INDEX = (N/2) - 1;

    // -------------------------------------------------------------------
    // Derived per-stage parameters (fft_size = 2^stage, half = fft_size/2)
    // -------------------------------------------------------------------
    reg [ADDR_W:0] fft_size;
    reg [ADDR_W-1:0] half;
    always @(*) begin
        fft_size = (1'b1 << stage);
        half     = fft_size >> 1'b1;
    end

    // -------------------------------------------------------------------
    // Butterfly addressing: g = index / half, k = index % half.
    // Same per-stage case table as the original fft_controller (verified
    // correct there) - kept explicit rather than a variable-shift/divide,
    // which some tool flows handle poorly. For STAGES other than 6,
    // mechanically add/remove case entries following the same pattern:
    // stage s -> half = 2^(s-1) -> g_tmp = index >> (s-1), k_tmp = index
    // masked to the low (s-1) bits.
    // -------------------------------------------------------------------
    reg [IDX_W-1:0] g_tmp, k_tmp;
    always @(*) begin
        case (stage)
            3'd1: begin g_tmp = index;        k_tmp = {IDX_W{1'b0}};        end
            3'd2: begin g_tmp = index >> 1;   k_tmp = index & {{IDX_W-1{1'b0}},1'b1};       end
            3'd3: begin g_tmp = index >> 2;   k_tmp = index & 5'b00011;     end
            3'd4: begin g_tmp = index >> 3;   k_tmp = index & 5'b00111;     end
            3'd5: begin g_tmp = index >> 4;   k_tmp = index & 5'b01111;     end
            3'd6: begin g_tmp = {IDX_W{1'b0}}; k_tmp = index;               end
            default: begin g_tmp = {IDX_W{1'b0}}; k_tmp = {IDX_W{1'b0}}; end
        endcase
    end

    wire [ADDR_W-1:0] addr_a_nat = ({g_tmp, 1'b0} * half) + k_tmp;
    wire [ADDR_W-1:0] addr_b_nat = addr_a_nat + half;
    wire [IDX_W-1:0]  twiddle_k  = k_tmp;

    function [ADDR_W-1:0] bitrev;
        input [ADDR_W-1:0] x;
        integer i;
        begin
            for (i = 0; i < ADDR_W; i = i + 1)
                bitrev[i] = x[ADDR_W-1-i];
        end
    endfunction

    wire [ADDR_W-1:0] addr_a_f = bitrev(addr_a_nat);
    wire [ADDR_W-1:0] addr_b_f = bitrev(addr_b_nat);

    // -------------------------------------------------------------------
    // Twiddle ROM (1-cycle latency, same as before)
    // -------------------------------------------------------------------
    wire rom_valid_in = (state == READ_MEM);
    wire signed [15:0] tw_re, tw_im;
    wire rom_valid_out;

    twiddle_rom #(.DATA_W(16), .ADDR_W(ADDR_W)) u_rom (
        .clk      (clk),
        .rst_n    (rst_n),
        .fft_size (fft_size),
        .k        (twiddle_k),
        .valid_in (rom_valid_in),
        .tw_re    (tw_re),
        .tw_im    (tw_im),
        .valid_out(rom_valid_out)
    );

    // -------------------------------------------------------------------
    // Butterfly (combinational)
    // -------------------------------------------------------------------
    wire signed [15:0] A_out_re, A_out_im, B_out_re, B_out_im;

    butterfly #(.DATA_W(16)) u_bfly (
        .A_re(dout_re_a), .A_im(dout_im_a),
        .B_re(dout_re_b), .B_im(dout_im_b),
        .W_re(tw_re),     .W_im(tw_im),
        .A_out_re(A_out_re), .A_out_im(A_out_im),
        .B_out_re(B_out_re), .B_out_im(B_out_im)
    );

    // Captured at the END of LATENCY -> stable throughout CALCULATE
    reg signed [15:0] cap_A_re, cap_A_im, cap_B_re, cap_B_im;

    // -------------------------------------------------------------------
    // Combinational RAM-facing signals - directly reflect current state.
    // -------------------------------------------------------------------
    assign we_a      = (state == CALCULATE);
    assign we_b      = (state == CALCULATE);
    assign addr_a    = addr_a_f;   // stable across READ_MEM..WRITE_MEM (stage/index unchanged)
    assign addr_b    = addr_b_f;
    assign din_re_a  = cap_A_re;
    assign din_im_a  = cap_A_im;
    assign din_re_b  = cap_B_re;
    assign din_im_b  = cap_B_im;

    assign done_calculate = (state == WRITE_MEM) &&
                             (stage == LAST_STAGE) && (index == LAST_INDEX);

    // -------------------------------------------------------------------
    // Next state
    // -------------------------------------------------------------------
    always @(*) begin
        next_state = state;
        case (state)
            IDLE:      next_state = start_calculate ? READ_MEM : IDLE;
            READ_MEM:  next_state = LATENCY;
            LATENCY:   next_state = CALCULATE;
            CALCULATE: next_state = WRITE_MEM;
            WRITE_MEM: next_state = done_calculate ? IDLE : READ_MEM;
            default:   next_state = IDLE;
        endcase
    end

    always @(posedge clk) begin
        if (!rst_n) state <= IDLE;
        else        state <= next_state;
    end

    // -------------------------------------------------------------------
    // Datapath
    // -------------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            stage    <= 3'd1;
            index    <= {IDX_W{1'b0}};
            cap_A_re <= 16'sd0; cap_A_im <= 16'sd0;
            cap_B_re <= 16'sd0; cap_B_im <= 16'sd0;
        end else begin
            case (state)
                IDLE: begin
                    if (start_calculate) begin
                        stage <= 3'd1;
                        index <= {IDX_W{1'b0}};
                    end
                end

                LATENCY: begin
                    // Butterfly output is combinational off dout_re_a/b,
                    // which are stable this cycle; latch for CALCULATE.
                    cap_A_re <= A_out_re; cap_A_im <= A_out_im;
                    cap_B_re <= B_out_re; cap_B_im <= B_out_im;
                end

                WRITE_MEM: begin
                    // Write already committed combinationally (see we_a/we_b
                    // above) on the edge entering this state. Advance the
                    // loop counters for the *next* READ_MEM here.
                    if (!done_calculate) begin
                        if (index == LAST_INDEX) begin
                            index <= {IDX_W{1'b0}};
                            stage <= stage + 3'd1;
                        end else begin
                            index <= index + 1'b1;
                        end
                    end
                end

                default: begin end
            endcase
        end
    end

endmodule