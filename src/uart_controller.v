module uart_controller(
	input wire clk, 
	input wire rst_n, 
    
    input rx_data, 
	output wire tx_serial
); 
	wire uart_axis_tvalid; 
	wire uart_axis_tready; 
	wire [15:0] uart_axis_tdata; 

	axi_uart_rx  uart_rx_module (
		.clk(clk), 
		.rst_n(rst_n), 
        .rx_data(rx_data), 
		.m_axis_tdata(uart_axis_tdata), 
		.m_axis_tready(uart_axis_tready), 
		.m_axis_tvalid(uart_axis_tvalid)
	);
    


	wire window_axis_tvalid;
	wire window_axis_tready;
	wire [15:0] window_axis_tdata; 
	axi_window window_module (
		.clk(clk), 
		.rst_n(rst_n), 
		.s_axis_tready(uart_axis_tready), 
		.s_axis_tvalid(uart_axis_tvalid),
		.s_axis_tdata(uart_axis_tdata),  
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