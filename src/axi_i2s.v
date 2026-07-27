module axi_i2s (
    input  wire clk,
    input  wire rst_n,

    input  wire sd,

    output wire bclk,
    output wire ws,

    output reg         m_axis_tvalid,
    input  wire        m_axis_tready,
    output reg [15:0]  m_axis_tdata
);

    wire        byte_ready;
    wire [23:0] audio_data;

    i2s i2s_u (
        .clk(clk),
        .bclk(bclk),
        .rst_n(rst_n),
        .ws(ws),
        .sd(sd),
        .byte_ready(byte_ready),
        .audio_data(audio_data)
    );

    // audio_data wired directly into din (not latched) -- per spec,
    // audio_data is held stable long enough relative to clk that this is safe
    wire [15:0] din = audio_data[23:8];
    wire [15:0] dout;
    wire        empty, full;

    reg rd_en, wr_en;

    fifo fifo_u (
        .rst_n(rst_n),
        .clk(clk),
        .wr_en(wr_en),
        .rd_en(rd_en),
        .din(din),
        .dout(dout),
        .empty(empty),
        .full(full)
    );

    //--------------------------------------------------------------
    // Write FSM
    //--------------------------------------------------------------
    localparam NO_WRITE   = 1'b0;
    localparam WRITE_WAIT = 1'b1;

    reg wstate;

    always @(posedge clk) begin
        if (!rst_n) begin
            wstate <= NO_WRITE;
            wr_en  <= 1'b0;
        end else begin
            case (wstate)
                NO_WRITE: begin
                    wr_en <= 1'b0;
                    if (byte_ready)
                        wstate <= WRITE_WAIT;
                end
                WRITE_WAIT: begin
                    wr_en <= 1'b1;
                    if (!full)
                        wstate <= NO_WRITE;
                end
            endcase
        end
    end

    //--------------------------------------------------------------
    // Collector FSM
    //--------------------------------------------------------------
    localparam NO_READ      = 2'd0;
    localparam READ_WAIT    = 2'd1;
    localparam READ_CAPTURE = 2'd2;
    localparam READ         = 2'd3;

    reg [1:0]  rstate;
    reg [15:0] data;

    always @(posedge clk) begin
        if (!rst_n) begin
            rstate        <= NO_READ;
            rd_en         <= 1'b0;
            data          <= 16'd0;
            m_axis_tdata  <= 16'd0;
            m_axis_tvalid <= 1'b0;
        end else begin
            case (rstate)
                NO_READ: begin
                    rd_en <= 1'b0;
                    if (!empty)
                        rstate <= READ_WAIT;
                end
                READ_WAIT: begin
                    rd_en  <= 1'b1;
                    rstate <= READ_CAPTURE;
                end
                READ_CAPTURE: begin
                    rd_en  <= 1'b0;
                    data   <= dout;
                    rstate <= READ;
                end
                READ: begin
                    m_axis_tdata  <= data;
                    m_axis_tvalid <= 1'b1;
                    if (m_axis_tvalid && m_axis_tready) begin
                        m_axis_tvalid <= 1'b0;
                        rstate        <= NO_READ;
                    end
                end
            endcase
        end
    end

endmodule