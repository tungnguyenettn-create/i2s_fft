// ---------------------------------------------------------------
// AXI-Stream -> UART wrapper.
// Consumes 16-bit log2 magnitude words from axi_output, one per
// FFT bin. Only transmits bins 0..MAX_BIN (real-FFT symmetry means
// bins above Nyquist are redundant); everything past MAX_BIN is
// still accepted (tready held high) but discarded, so axi_output
// never stalls waiting on us. bin_count resets on tlast.
// ---------------------------------------------------------------
module axi_uart_tx #(
    parameter CLKS_PER_BIT = 9,   // 27 MHz / 3 Mbit/s
    parameter MAX_BIN      = 32   // bins 0..32 -> 33 bins sent per frame
)(
    input  clk,
    input  rst_n,

    input        s_axis_tvalid,
    output reg   s_axis_tready,
    input [15:0] s_axis_tdata,
    input        s_axis_tlast,

    output       uart_tx_serial
);

    localparam IDLE    = 3'd0;
    localparam SKIP    = 3'd1;
    localparam SEND_HI = 3'd2;
    localparam WAIT_HI = 3'd3;
    localparam SEND_LO = 3'd4;
    localparam WAIT_LO = 3'd5;

    reg [2:0]  state;
    reg [5:0]  bin_count;   // 0..63
    reg [15:0] data_reg;
    reg        tx_start;
    reg [7:0]  tx_byte;
    wire       tx_busy;
    wire       tx_done;

    wire hs = s_axis_tvalid && s_axis_tready;

    uart_tx_byte #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_txbyte (
        .clk       (clk),
        .rst_n     (rst_n),
        .tx_start  (tx_start),
        .tx_data   (tx_byte),
        .tx_busy   (tx_busy),
        .tx_serial (uart_tx_serial),
        .tx_done   (tx_done)
    );

    always @(posedge clk) begin
        if (!rst_n) begin
            state         <= IDLE;
            s_axis_tready <= 1'b1;
            bin_count     <= 6'd0;
            tx_start      <= 1'b0;
        end else begin
            tx_start <= 1'b0; // default: one-cycle pulse
            case (state)
                IDLE: begin
                    s_axis_tready <= 1'b1;
                    if (hs) begin
                        data_reg  <= s_axis_tdata;
                        bin_count <= s_axis_tlast ? 6'd0 : bin_count + 1'b1;
                        if (bin_count <= MAX_BIN) begin
                            s_axis_tready <= 1'b0; // hold off next beat while sending
                            state         <= SEND_HI;
                        end else begin
                            state <= SKIP; // discard, stay effectively ready
                        end
                    end
                end
                SKIP: state <= IDLE; // one bookkeeping cycle, back to ready
                SEND_HI: begin
                    tx_byte  <= data_reg[15:8];
                    tx_start <= 1'b1;
                    state    <= WAIT_HI;
                end
                WAIT_HI: if (tx_done) state <= SEND_LO;
                SEND_LO: begin
                    tx_byte  <= data_reg[7:0];
                    tx_start <= 1'b1;
                    state    <= WAIT_LO;
                end
                WAIT_LO: begin
                    if (tx_done) begin
                        s_axis_tready <= 1'b1;
                        state         <= IDLE;
                    end
                end
            endcase
        end
    end
endmodule