module i2s(
    input  clk,
    output bclk,
    input  rst_n,
    output reg ws,
    input  sd,
    output reg byte_ready,
    output reg [23:0] audio_data   // INMP441 outputs 24 valid bits per 32-bit slot
);

    //--------------------------------------------------------------
    // BCLK generation
    // clk = 27 MHz, period = 10 clk cycles -> BCLK = 2.7 MHz
    // fs = BCLK / 64 = 42.1875 kHz  (64 BCLK cycles per WS/LRCK period)
    //--------------------------------------------------------------
    reg [3:0] clk_counter;
    reg       bclk_reg;
    reg       bclk_prev;
    wire      bclk_falling, bclk_rising;

    assign bclk = bclk_reg;
    assign bclk_falling = (bclk_prev == 1'b1) && (bclk_reg == 1'b0);
    assign bclk_rising  = (bclk_prev == 1'b0) && (bclk_reg == 1'b1);

    //--------------------------------------------------------------
    // WS (LRCK) generation: toggles every 32 BCLK falling edges
    // -> WS period = 64 BCLK cycles (32-bit slot per channel)
    //--------------------------------------------------------------
    reg [5:0] ws_counter;
    reg       ws_prev;
    wire      ws_falling_edge;

    assign ws_falling_edge = (ws_prev == 1'b1) && (ws == 1'b0);

    //--------------------------------------------------------------
    // RX FSM
    //--------------------------------------------------------------
    localparam rxIDLE  = 2'd0;
    localparam rxSTART = 2'd1;
    localparam rxREAD  = 2'd2;
    localparam rxDONE  = 2'd3;

    reg [1:0] rxState;
    reg [1:0] rxNextState;
    reg [4:0] rxBitCount;      // 0..23 -> need 5 bits
    reg [23:0] shift_reg;

    always @(*) begin
        rxNextState = rxState;
        case (rxState)
            rxIDLE:  rxNextState = (ws_falling_edge) ? rxSTART : rxIDLE;
            rxSTART: rxNextState = (bclk_falling) ? rxREAD : rxSTART;
            rxREAD:  rxNextState = (bclk_rising && rxBitCount == 5'd23) ? rxDONE : rxREAD;
            rxDONE:  rxNextState = rxIDLE;
            default: rxNextState = rxIDLE;
        endcase
    end

    //--------------------------------------------------------------
    // Single reset domain, single driver per register
    //--------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            clk_counter <= 0;
            bclk_reg    <= 0;
            bclk_prev   <= 0;
        end else begin
            if (clk_counter < 4'd9) clk_counter <= clk_counter + 1'b1;
            else clk_counter <= 0;

            if (clk_counter < 4'd5) bclk_reg <= 1'b1;
            else bclk_reg <= 1'b0;

            bclk_prev <= bclk_reg;
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            ws         <= 1'b0;
            ws_prev    <= 1'b0;
            ws_counter <= 0;
        end else begin
            ws_prev <= ws;
            if (bclk_falling) begin
                if (ws_counter < 6'd31) begin
                    ws_counter <= ws_counter + 1'b1;
                end else begin
                    ws_counter <= 0;
                    ws <= ~ws;
                end
            end
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            rxState    <= rxIDLE;
            rxBitCount <= 0;
            byte_ready <= 1'b0;
            shift_reg  <= 0;
            audio_data <= 0;
        end else begin
            rxState <= rxNextState;
            case (rxState)
                rxIDLE: begin
                    byte_ready <= 1'b0;
                    rxBitCount <= 0;
                end
                rxSTART: begin
                    rxBitCount <= 0;
                    byte_ready <= 1'b0;
                end
                rxREAD: begin
                    if (bclk_rising) begin
                        shift_reg <= {shift_reg[22:0], sd};
                        if (rxBitCount < 5'd23) rxBitCount <= rxBitCount + 1'b1;
                    end
                end
                rxDONE: begin
                    audio_data <= shift_reg;
                    byte_ready <= 1'b1;
                end
                default: byte_ready <= 1'b0;
            endcase
        end
    end

endmodule