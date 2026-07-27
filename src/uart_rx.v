module uart_rx #(
    parameter CLKS_PER_BIT = 9,
    parameter COUNTER_LEN  = $clog2(CLKS_PER_BIT) 
)(
    input clk, 
    input rst_n, 
    input rx_data, 
    output reg [7:0] rx_byte,  
    output reg byte_ready 
); 

    localparam IDLE  = 3'd0; 
    localparam START = 3'd1; 
    localparam DATA  = 3'd2; 
    localparam STOP  = 3'd3; 

    reg [2:0] state; 
    reg [COUNTER_LEN-1:0] counter; 
    reg [2:0] bit_counter; 
    
    // Double-flop synchronizer to prevent metastability
    reg cap_data, cap_data1; 

    always @(posedge clk or negedge rst_n) begin 
        if (!rst_n) begin
            cap_data  <= 1'b1; // UART idles high
            cap_data1 <= 1'b1;
        end else begin
            cap_data  <= rx_data; 
            cap_data1 <= cap_data; // Pass data through the sync chain
        end 
    end 

    // Main UART Receiver State Machine
    always @(posedge clk or negedge rst_n) begin 
        if (!rst_n) begin 
            state       <= IDLE; 
            rx_byte     <= 8'd0; 
            counter     <= 0;
            byte_ready  <= 1'b0; // Reset to 0
            bit_counter <= 0;
        end else begin 
            // Default assignment to ensure byte_ready acts as a 1-clock pulse
            byte_ready <= 1'b0; 

            case (state)
                IDLE: begin 
                    counter     <= 0;
                    bit_counter <= 0;
                    // Start bit detected (line goes LOW)
                    if (cap_data1 == 1'b0) begin 
                        state <= START;
                    end 
                end 

                START: begin 
                    // Wait to reach the middle of the start bit
                    if (counter == (CLKS_PER_BIT / 2)) begin 
                        if (cap_data1 == 1'b0) begin // Verify it's still low (not a glitch)
                            counter <= 0;
                            state   <= DATA; 
                        end else begin
                            state   <= IDLE; 
                        end
                    end else begin
                        counter <= counter + 1'b1;
                    end
                end 

                DATA: begin 
                    // Wait for the full bit period to sample the next bit
                    if (counter < CLKS_PER_BIT - 1) begin 
                        counter <= counter + 1'b1; 
                    end else begin 
                        counter <= 0; 
                        // Shift data in LSB first
                        rx_byte <= {cap_data1, rx_byte[7:1]};  
                        
                        // Check if we have received all 8 bits
                        if (bit_counter < 3'd7) begin 
                            bit_counter <= bit_counter + 1'b1; 
                        end else begin 
                            bit_counter <= 0; 
                            state       <= STOP; 
                        end 
                    end 
                end

                STOP: begin
                    // Wait for the full bit period of the Stop Bit
                    if (counter < CLKS_PER_BIT - 1) begin
                        counter <= counter + 1'b1;
                    end else begin
                        byte_ready <= 1'b1; // Pulse valid data flag
                        state      <= IDLE; // Return to wait for next byte
                    end
                end

                default: state <= IDLE;
            endcase
        end 
    end    
endmodule