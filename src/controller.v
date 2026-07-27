module controller(
	input wire clk, 
	input wire rst_n, 

	input wire sd, 


	output wire bclk,
	output wire ws, 

	output wire tx_serial
); 
	wire i2s_axis_tvalid; 
	wire i2s_axis_tready; 
	wire [15:0] i2s_axis_tdata; 

	axi_i2s  i2s_module (
		.clk(clk), 
		.rst_n(rst_n), 
		.sd(sd), 
		.bclk(bclk), 
        .ws(ws),
		.m_axis_tdata(i2s_axis_tdata), 
		.m_axis_tready(i2s_axis_tready), 
		.m_axis_tvalid(i2s_axis_tvalid)
	);

	wire window_axis_tvalid;
	wire window_axis_tready;
	wire [15:0] window_axis_tdata; 
	axi_window window_module (
		.clk(clk), 
		.rst_n(rst_n), 
		.s_axis_tready(i2s_axis_tready), 
		.s_axis_tvalid(i2s_axis_tvalid),
		.s_axis_tdata(i2s_axis_tdata),  
		.m_axis_tready(window_axis_tready), 
		.m_axis_tdata(window_axis_tdata), 
		.m_axis_tvalid(window_axis_tvalid)
	);

	wire fft_axis_tvalid; 
	wire fft_axis_tready; 
	wire [31:0] fft_axis_tdata;
	wire fft_axis_tlast; 

	axi_fft_top fft_module (
		.clk(clk),
		.rst_n(rst_n), 
		.frame_trigger(1'b1), //This is unncessary cause window only stream data when data existed correctly 
		.s_axis_tready(window_axis_tready), 
		.s_axis_tvalid(window_axis_tvalid), 
		.s_axis_tdata(window_axis_tdata),

		.m_axis_tready(fft_axis_tready), 
		.m_axis_tvalid(fft_axis_tvalid), 
		.m_axis_tdata(fft_axis_tdata), 
		.m_axis_tlast(fft_axis_tlast)
	);

	wire log_axis_tvalid; 
	wire log_axis_tready; 
	wire [15:0] log_axis_tdata; 
	wire log_axis_tlast;

	axi_output log_module(
		.clk(clk), 
		.rst_n(rst_n), 
		.s_axis_tready(fft_axis_tready), 
		.s_axis_tvalid(fft_axis_tvalid), 
		.s_axis_tdata(fft_axis_tdata), 
		.s_axis_tlast(fft_axis_tlast), 
		.m_axis_tready(log_axis_tready), 
		.m_axis_tvalid(log_axis_tvalid), 
		.m_axis_tdata(log_axis_tdata), 
		.m_axis_tlast(log_axis_tlast)
	);  

	axi_uart_tx uart_module(
		.clk(clk), 
		.rst_n(rst_n), 
		.s_axis_tready(log_axis_tready), 
		.s_axis_tvalid(log_axis_tvalid), 
		.s_axis_tdata(log_axis_tdata), 
		.s_axis_tlast(log_axis_tlast), 
		.uart_tx_serial(tx_serial) 
	);
endmodule 