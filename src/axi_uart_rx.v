module axi_uart_rx #(
	parameter CLKS_PER_BIT = 9 
) (
	input clk, 
	input rst_n, 
	input rx_data,  

	input m_axis_tready, 
	output reg m_axis_tvalid,  
	output reg [15:0] m_axis_tdata  
); 
	wire   byte_ready;  
	reg [15:0] audio_data; 
	wire [7:0] byte_data; 

	uart_rx #(
        .CLKS_PER_BIT(CLKS_PER_BIT)
    ) uart_u (
		.clk(clk), 
		.rst_n(rst_n), 
		.rx_data(rx_data), 
		.byte_ready(byte_ready), 
		.rx_byte(byte_data) 
	); 



	//Assume send high byte before send low byte 
	wire [15:0] din = audio_data; 
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
    localparam ASSEMBLE   = 2'd0; 
    localparam WRITE_WAIT = 2'd1; 

    reg [1:0] wstate; 
    reg       byte_count; // Only needs to count 0 or 1 for 2 bytes

    always @(posedge clk) begin 
        if(!rst_n) begin 
            wstate     <= ASSEMBLE; 
            byte_count <= 1'b0; 
            wr_en      <= 1'b0;
            audio_data <= 16'd0;
        end else begin 
            wr_en <= 1'b0; // Default: don't write unless explicitly told to

            case (wstate) 
                ASSEMBLE: begin 
                    if (byte_ready) begin 
                        // Shift left: High byte arrives first, ends up in MSB
                        audio_data <= {audio_data[7:0], byte_data};
                        
                        if (byte_count == 1'b1) begin 
                            byte_count <= 1'b0; 
                            wstate     <= WRITE_WAIT; 
                        end else begin
                            byte_count <= byte_count + 1'b1;
                        end
                    end 
                end 
                
                WRITE_WAIT: begin 
                    if (!full) begin 
                        wr_en  <= 1'b1; // Pulses for exactly 1 cycle due to default assignment
                        wstate <= ASSEMBLE;  
                    end 
                end

                default: wstate <= ASSEMBLE;
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