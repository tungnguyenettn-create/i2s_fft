module axi_output (
    input  clk,
    input  rst_n,

    input  s_axis_tvalid,
    output reg s_axis_tready,
    input  [31:0] s_axis_tdata,
    input  s_axis_tlast,

    output reg m_axis_tvalid,
    input  m_axis_tready,
    output reg [15:0] m_axis_tdata,   // Q6.10 log2 magnitude (1 sign, 5 int, 10 frac)
    output reg m_axis_tlast
);

    wire signed [15:0] re  = $signed(s_axis_tdata[31:16]);
    wire signed [15:0] im  = $signed(s_axis_tdata[15:0]);
    wire signed [31:0] re_prod = re * re;
    wire signed [31:0] im_prod = im * im;
    
    
    wire [30:0] re_truncated = re_prod[30:0]; //The first bit is unnecessary it can't be negative 
    wire [30:0] im_truncated = im_prod[30:0];  
    reg  [31:0] cap_prod;        // No truncation, there is no sign bit here, the first bit is 2 
    reg signed  [5:0]  int_part;     // leading-zero mapped integer exponent
    reg        tlast_d;

    localparam IDLE = 3'd0;
    localparam SUM  = 3'd1;
    localparam LOG  = 3'd2;
    localparam INT  = 3'd3;  // LUT Read Stage
    localparam OUT  = 3'd4;

    reg [2:0] state;
    wire shs = s_axis_tvalid && s_axis_tready;

    // --- Pipelined Fractional Part Registers ---
    reg [31:0] norm_cap;
    reg [10:0] lut_y0;
    reg [10:0] lut_delta; 
    
    // Use the top 4 bits of the mantissa to index the LUT
    wire [3:0]  lut_idx = norm_cap[30:27];
    // Use the remaining 12 bits for linear interpolation
    wire [11:0] lut_rem = norm_cap[26:15];

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
                    if (cap_prod == 32'd0) begin
                        cap_prod <= 32'd1;
                    end
                    state <= LOG;
                end

                LOG: begin
                    // Priority encoder & Barrel Shifter
                    casez (cap_prod)
                        32'b1???_????_????_????_????_????_????_????: begin
                            int_part <= 6'sd1;
                            norm_cap <= cap_prod; // Shift 0
                        end
                        32'b01??_????_????_????_????_????_????_????: begin
                            int_part <= 6'sd0;
                            norm_cap <= cap_prod << 6'd1;
                        end
                        32'b001?_????_????_????_????_????_????_????: begin
                            int_part <= -6'sd1;
                            norm_cap <= cap_prod << 6'd2;
                        end
                        32'b0001_????_????_????_????_????_????_????: begin
                            int_part <= -6'sd2;
                            norm_cap <= cap_prod << 6'd3;
                        end
                        32'b0000_1???_????_????_????_????_????_????: begin
                            int_part <= -6'sd3;
                            norm_cap <= cap_prod << 6'd4;
                        end
                        32'b0000_01??_????_????_????_????_????_????: begin
                            int_part <= -6'sd4;
                            norm_cap <= cap_prod << 6'd5;
                        end
                        32'b0000_001?_????_????_????_????_????_????: begin
                            int_part <= -6'sd5;
                            norm_cap <= cap_prod << 6'd6;
                        end
                        32'b0000_0001_????_????_????_????_????_????: begin
                            int_part <= -6'sd6;
                            norm_cap <= cap_prod << 6'd7;
                        end
                        32'b0000_0000_1???_????_????_????_????_????: begin
                            int_part <= -6'sd7;
                            norm_cap <= cap_prod << 6'd8;
                        end
                        32'b0000_0000_01??_????_????_????_????_????: begin
                            int_part <= -6'sd8;
                            norm_cap <= cap_prod << 6'd9;
                        end
                        32'b0000_0000_001?_????_????_????_????_????: begin
                            int_part <= -6'sd9;
                            norm_cap <= cap_prod << 6'd10;
                        end
                        32'b0000_0000_0001_????_????_????_????_????: begin
                            int_part <= -6'sd10;
                            norm_cap <= cap_prod << 6'd11;
                        end
                        32'b0000_0000_0000_1???_????_????_????_????: begin
                            int_part <= -6'sd11;
                            norm_cap <= cap_prod << 6'd12;
                        end
                        32'b0000_0000_0000_01??_????_????_????_????: begin
                            int_part <= -6'sd12;
                            norm_cap <= cap_prod << 6'd13;
                        end
                        32'b0000_0000_0000_001?_????_????_????_????: begin
                            int_part <= -6'sd13;
                            norm_cap <= cap_prod << 6'd14;
                        end
                        32'b0000_0000_0000_0001_????_????_????_????: begin
                            int_part <= -6'sd14;
                            norm_cap <= cap_prod << 6'd15;
                        end
                        32'b0000_0000_0000_0000_1???_????_????_????: begin
                            int_part <= -6'sd15;
                            norm_cap <= cap_prod << 6'd16;
                        end
                        32'b0000_0000_0000_0000_01??_????_????_????: begin
                            int_part <= -6'sd16;
                            norm_cap <= cap_prod << 6'd17;
                        end
                        32'b0000_0000_0000_0000_001?_????_????_????: begin
                            int_part <= -6'sd17;
                            norm_cap <= cap_prod << 6'd18;
                        end
                        32'b0000_0000_0000_0000_0001_????_????_????: begin
                            int_part <= -6'sd18;
                            norm_cap <= cap_prod << 6'd19;
                        end
                        32'b0000_0000_0000_0000_0000_1???_????_????: begin
                            int_part <= -6'sd19;
                            norm_cap <= cap_prod << 6'd20;
                        end
                        32'b0000_0000_0000_0000_0000_01??_????_????: begin
                            int_part <= -6'sd20;
                            norm_cap <= cap_prod << 6'd21;
                        end
                        32'b0000_0000_0000_0000_0000_001?_????_????: begin
                            int_part <= -6'sd21;
                            norm_cap <= cap_prod << 6'd22;
                        end
                        32'b0000_0000_0000_0000_0000_0001_????_????: begin
                            int_part <= -6'sd22;
                            norm_cap <= cap_prod << 6'd23;
                        end
                        32'b0000_0000_0000_0000_0000_0000_1???_????: begin
                            int_part <= -6'sd23;
                            norm_cap <= cap_prod << 6'd24;
                        end
                        32'b0000_0000_0000_0000_0000_0000_01??_????: begin
                            int_part <= -6'sd24;
                            norm_cap <= cap_prod << 6'd25;
                        end
                        32'b0000_0000_0000_0000_0000_0000_001?_????: begin
                            int_part <= -6'sd25;
                            norm_cap <= cap_prod << 6'd26;
                        end
                        32'b0000_0000_0000_0000_0000_0000_0001_????: begin
                            int_part <= -6'sd26;
                            norm_cap <= cap_prod << 6'd27;
                        end
                        32'b0000_0000_0000_0000_0000_0000_0000_1???: begin
                            int_part <= -6'sd27;
                            norm_cap <= cap_prod << 6'd28;
                        end
                        32'b0000_0000_0000_0000_0000_0000_0000_01??: begin
                            int_part <= -6'sd28;
                            norm_cap <= cap_prod << 6'd29;
                        end
                        32'b0000_0000_0000_0000_0000_0000_0000_001?: begin
                            int_part <= -6'sd29;
                            norm_cap <= cap_prod << 6'd30;
                        end
                        32'b0000_0000_0000_0000_0000_0000_0000_0001: begin
                            int_part <= -6'sd30;
                            norm_cap <= cap_prod << 6'd31;
                        end
                        default: begin
                            int_part <= -6'sd31; // Zero case
                            norm_cap <= 32'd0;
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
                    m_axis_tdata  <= {int_part, frac_part}; 
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