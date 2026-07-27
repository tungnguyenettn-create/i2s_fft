module axi_output (
    input  clk,
    input  rst_n,

    input  s_axis_tvalid,
    output reg s_axis_tready,
    input  [31:0] s_axis_tdata,
    input  s_axis_tlast,

    output reg m_axis_tvalid,
    input  m_axis_tready,
    output reg [15:0] m_axis_tdata,   // Q5.10 log2 magnitude (1 sign, 5 int, 10 frac)
    output reg m_axis_tlast
);

    wire signed [15:0] re  = $signed(s_axis_tdata[31:16]);
    wire signed [15:0] im  = $signed(s_axis_tdata[15:0]);
    wire signed [31:0] re_prod = re * re;
    wire signed [31:0] im_prod = im * im;
    
    // Shifted to fit sums into 17 bits comfortably. 
    // Kept unsigned to avoid the sign-extension bug!
    wire [15:0] re_truncated = re_prod[30:15];
    wire [15:0] im_truncated = im_prod[30:15];

    reg [16:0] cap_prod;     // re_truncated + im_truncated, always >=0
    reg [4:0]  int_part;     // leading-zero mapped integer exponent
    reg        tlast_d;

    localparam IDLE = 3'd0;
    localparam SUM  = 3'd1;
    localparam LOG  = 3'd2;
    localparam INT  = 3'd3;  // LUT Read Stage
    localparam OUT  = 3'd4;

    reg [2:0] state;
    wire shs = s_axis_tvalid && s_axis_tready;

    // --- Pipelined Fractional Part Registers ---
    reg [16:0] norm_cap;
    reg [10:0] lut_y0;
    reg [10:0] lut_delta; 
    
    // Use the top 4 bits of the mantissa to index the LUT
    wire [3:0]  lut_idx = norm_cap[15:12];
    // Use the remaining 12 bits for linear interpolation
    wire [11:0] lut_rem = norm_cap[11:0];

    // 17-entry LUT for log2(1.x) * 1024
    reg [10:0] log2_lut [0:16];
    initial begin
        log2_lut[0]  = 11'd0;    // log2(1.0) * 1024
        log2_lut[1]  = 11'd89;   // log2(1.0625)
        log2_lut[2]  = 11'd174;  // log2(1.125)
        log2_lut[3]  = 11'd255;  // log2(1.1875)
        log2_lut[4]  = 11'd330;  // log2(1.25)
        log2_lut[5]  = 11'd401;  // log2(1.3125)
        log2_lut[6]  = 11'd469;  // log2(1.375)
        log2_lut[7]  = 11'd534;  // log2(1.4375)
        log2_lut[8]  = 11'd599;  // log2(1.5)
        log2_lut[9]  = 11'd660;  // log2(1.5625)
        log2_lut[10] = 11'd717;  // log2(1.625)
        log2_lut[11] = 11'd773;  // log2(1.6875)
        log2_lut[12] = 11'd827;  // log2(1.75)
        log2_lut[13] = 11'd879;  // log2(1.8125)
        log2_lut[14] = 11'd929;  // log2(1.875)
        log2_lut[15] = 11'd977;  // log2(1.9375)
        log2_lut[16] = 11'd1024; // log2(2.0)
    end

    // Interpolation happens combinationally using the registered values from INT stage.
    // This perfectly breaks the critical path!
    wire [22:0] interp_term = lut_delta * lut_rem; 
    wire [9:0]  frac_part   = lut_y0[9:0] + interp_term[21:12]; // Fixed 11-bit mismatch warning

    // ----------------------------------------------------

    always @(posedge clk) begin
        if (!rst_n) begin
            state         <= IDLE;
            s_axis_tready <= 1'b1;
            m_axis_tvalid <= 1'b0;
            cap_prod      <= 17'd0;
            int_part      <= 5'd16;
            norm_cap      <= 17'd0;
            lut_y0        <= 11'd0;
            lut_delta     <= 11'd0;
        end else begin
            case (state)
                IDLE: begin
                    s_axis_tready <= 1'b1;
                    if (shs) begin
                        cap_prod      <= re_truncated + im_truncated; // Step 1: square+sum
                        tlast_d       <= s_axis_tlast;
                        s_axis_tready <= 1'b0;
                        state         <= SUM;
                    end
                end

                SUM: begin
                    // Clamp to epsilon floor (1) to avoid log2(0) going to -infinity
                    if (cap_prod == 17'd0) begin
                        cap_prod <= 17'd1;
                    end
                    state <= LOG;
                end

                LOG: begin
                    // Priority encoder & Barrel Shifter
                    casex (cap_prod)
                        17'b1_????_????_????_????: begin
                            int_part <= 5'd16;
                            norm_cap <= cap_prod; // No shift needed
                        end
                        17'b0_1???_????_????_????: begin
                            int_part <= 5'd15;
                            norm_cap <= cap_prod << 5'd1;
                        end
                        17'b0_01??_????_????_????: begin
                            int_part <= 5'd14;
                            norm_cap <= cap_prod << 5'd2;
                        end
                        17'b0_001?_????_????_????: begin
                            int_part <= 5'd13;
                            norm_cap <= cap_prod << 5'd3;
                        end
                        17'b0_0001_????_????_????: begin
                            int_part <= 5'd12;
                            norm_cap <= cap_prod << 5'd4;
                        end
                        17'b0_0000_1???_????_????: begin
                            int_part <= 5'd11;
                            norm_cap <= cap_prod << 5'd5;
                        end
                        17'b0_0000_01??_????_????: begin
                            int_part <= 5'd10;
                            norm_cap <= cap_prod << 5'd6;
                        end
                        17'b0_0000_001?_????_????: begin
                            int_part <= 5'd9;
                            norm_cap <= cap_prod << 5'd7;
                        end
                        17'b0_0000_0001_????_????: begin
                            int_part <= 5'd8;
                            norm_cap <= cap_prod << 5'd8;
                        end
                        17'b0_0000_0000_1???_????: begin
                            int_part <= 5'd7;
                            norm_cap <= cap_prod << 5'd9;
                        end
                        17'b0_0000_0000_01??_????: begin
                            int_part <= 5'd6;
                            norm_cap <= cap_prod << 5'd10;
                        end
                        17'b0_0000_0000_001?_????: begin
                            int_part <= 5'd5;
                            norm_cap <= cap_prod << 5'd11;
                        end
                        17'b0_0000_0000_0001_????: begin
                            int_part <= 5'd4;
                            norm_cap <= cap_prod << 5'd12;
                        end
                        17'b0_0000_0000_0000_1???: begin
                            int_part <= 5'd3;
                            norm_cap <= cap_prod << 5'd13;
                        end
                        17'b0_0000_0000_0000_01??: begin
                            int_part <= 5'd2;
                            norm_cap <= cap_prod << 5'd14;
                        end
                        17'b0_0000_0000_0000_001?: begin
                            int_part <= 5'd1;
                            norm_cap <= cap_prod << 5'd15;
                        end
                        default: begin
                            int_part <= 5'd0;
                            norm_cap <= cap_prod << 5'd16; 
                        end
                    endcase
                    state <= INT; 
                end

                INT: begin 
                    // Pipeline Stage: Read LUT and calculate Delta
                    lut_y0    <= log2_lut[lut_idx];
                    lut_delta <= log2_lut[lut_idx + 1] - log2_lut[lut_idx];  
                    state     <= OUT; // Re-added the missing transition!
                end 
                
                OUT: begin
                    m_axis_tdata  <= {1'b0, int_part, frac_part}; 
                    m_axis_tlast  <= tlast_d;
                    m_axis_tvalid <= 1'b1;
                    
                    if (m_axis_tvalid && m_axis_tready) begin
                        m_axis_tvalid <= 1'b0;
                        s_axis_tready <= 1'b1;
                        state         <= IDLE;
                    end
                end
            endcase
        end
    end
endmodule