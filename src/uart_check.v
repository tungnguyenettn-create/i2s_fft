module uart_check (
    input clk, 
    input rst_n, 
    input rx_data, 
    
    output tx_serial 
);
    wire rx_valid;  
    wire tx_ready;
    wire [15:0] audio_data;
    axi_uart_rx 
    #(
    .CLKS_PER_BIT(234)
    )
    uart_rx
    (
        .clk(clk), 
        .rst_n(rst_n),
        .rx_data(rx_data),
        .m_axis_tready(tx_ready),
        .m_axis_tvalid(rx_valid), 
        .m_axis_tdata(audio_data)
    ); 
    axi_uart_tx 
    #(
    .CLKS_PER_BIT(234)
    )
    uart_tx
    (
        .clk(clk),
        .rst_n(rst_n),
        .s_axis_tvalid(rx_valid), 
        .s_axis_tready(tx_ready), 
        .s_axis_tdata(audio_data),
        .s_axis_tlast(1'b0),  
        .uart_tx_serial(tx_serial)
    );
endmodule 