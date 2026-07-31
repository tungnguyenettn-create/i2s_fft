// ---------------------------------------------------------------
// Simple UART transmitter: one byte at a time, 8N1 framing.
// ---------------------------------------------------------------
module uart_tx_byte #(
    parameter CLKS_PER_BIT = 9,   // 27 MHz / 3 Mbit/s
    parameter COUNTER_LEN  = $clog2(CLKS_PER_BIT)
)(
    input        clk,
    input        rst_n,
    input        tx_start,   // one-cycle pulse to begin sending tx_data
    input  [7:0] tx_data,
    output reg   tx_busy,
    output reg   tx_serial,  // idle-high serial line
    output reg   tx_done     // one-cycle pulse when stop bit finishes
);
    localparam IDLE  = 2'd0;
    localparam START = 2'd1;
    localparam DATA  = 2'd2;
    localparam STOP  = 2'd3;

    reg [1:0] state;
    reg [COUNTER_LEN-1:0] clk_cnt;
    reg [2:0] bit_idx;
    reg [7:0] data_reg;

    always @(posedge clk) begin
        if (!rst_n) begin
            state     <= IDLE;
            tx_serial <= 1'b1;
            tx_busy   <= 1'b0;
            tx_done   <= 1'b0;
            clk_cnt   <= 0;
            bit_idx   <= 0;
        end else begin
            tx_done <= 1'b0; // default: pulse
            case (state)
                IDLE: begin
                    tx_serial <= 1'b1;
                    if (tx_start) begin
                        data_reg <= tx_data;
                        tx_busy  <= 1'b1;
                        clk_cnt  <= 0;
                        state    <= START;
                    end
                end
                START: begin
                    tx_serial <= 1'b0; // start bit
                    if (clk_cnt == CLKS_PER_BIT-1) begin
                        clk_cnt <= 0;
                        bit_idx <= 0;
                        state   <= DATA;
                    end else
                        clk_cnt <= clk_cnt + 1'b1;
                end
                DATA: begin
                    tx_serial <= data_reg[bit_idx]; // LSB first
                    if (clk_cnt == CLKS_PER_BIT-1) begin
                        clk_cnt <= 0;
                        if (bit_idx == 3'd7)
                            state <= STOP;
                        else
                            bit_idx <= bit_idx + 1'b1;
                    end else
                        clk_cnt <= clk_cnt + 1'b1;
                end
                STOP: begin
                    tx_serial <= 1'b1; // stop bit
                    if (clk_cnt == CLKS_PER_BIT-1) begin
                        clk_cnt <= 0;
                        tx_busy <= 1'b0;
                        tx_done <= 1'b1;
                        state   <= IDLE;
                    end else
                        clk_cnt <= clk_cnt + 1'b1;
                end
            endcase
        end
    end
endmodule