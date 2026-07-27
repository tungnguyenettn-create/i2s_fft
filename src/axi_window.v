module axi_window #(
    parameter WINDOW_SIZE = 64,
    parameter HOP_SIZE = 32, 
    parameter BUFFER_DEPTH = 128,
    parameter ADDRESS_MEM = $clog2(BUFFER_DEPTH)
)
(
    input clk, 
    input rst_n, 

    input s_axis_tvalid,
    input [15:0] s_axis_tdata,
    output reg s_axis_tready, 

    output reg m_axis_tvalid, 
    input m_axis_tready, 
    output reg [15:0] m_axis_tdata 
); 
    
    reg [15:0] memory_bank [0:BUFFER_DEPTH-1]; 
    
    // ---- Ingest module ----
    // Single always-ready state, no separate WRITE state -- this part
    // of the original design was already correct: TDATA is guaranteed
    // valid exactly when TVALID&&TREADY are both high, so capture and
    // commit can happen in the same cycle.
    localparam IIDLE       = 2'd0; 
    localparam WRITE_READY = 2'd1; 

    reg [1:0] istate; 
    reg [ADDRESS_MEM-1:0] write_ptr; 
    wire shs = (s_axis_tvalid) && (s_axis_tready); 
    wire [ADDRESS_MEM-1:0] write_ptr_next = write_ptr + 1'b1;

    // FIX (was Bug G): registered one-cycle pulses instead of level
    // signals off write_ptr's low bits. A level can re-trigger (or
    // fail to trigger promptly) if write_ptr ever sits still on a
    // boundary value; a pulse only fires the exact cycle the pointer
    // crosses it.
    reg _32_bit_hop; 
    reg init_64_point_valid; 
    reg init_fired;

    always @(posedge clk) begin 
        if (!rst_n) begin 
            istate       <= IIDLE; 
            s_axis_tready <= 0;
            write_ptr    <= {ADDRESS_MEM{1'b0}}; 
            _32_bit_hop  <= 1'b0;
            init_64_point_valid <= 1'b0;
            init_fired   <= 1'b0;
        end 
        else begin
            _32_bit_hop         <= 1'b0;  // pulse defaults
            init_64_point_valid <= 1'b0;
            case (istate) 
                IIDLE: begin 
                    s_axis_tready <= 1;
                    write_ptr     <= {ADDRESS_MEM{1'b0}};  
                    init_fired    <= 1'b0;
                    istate        <= WRITE_READY; 
                end 
                WRITE_READY: begin 
                    if (shs) begin 
                        memory_bank[write_ptr] <= s_axis_tdata; 
                        write_ptr <= write_ptr_next; 

                        // FIX (was Bug B): exact equality on the sample
                        // count, not `~|write_ptr[4:0] & write_ptr[5]`,
                        // which fires at write_ptr==32 (bit 5 is only
                        // set at 32/96), never at the intended 64.
                        if (write_ptr_next == WINDOW_SIZE[ADDRESS_MEM-1:0] && !init_fired) begin
                            init_64_point_valid <= 1'b1;
                            init_fired          <= 1'b1;
                        end

                        // Hop pulse: every HOP_SIZE samples.
                        if (write_ptr_next[4:0] == 5'b0)
                            _32_bit_hop <= 1'b1;
                    end 
                end 
                default: istate <= IIDLE;
            endcase 
        end
    end 

    // ---- Master state machine ----
    // FIX (was Bug E): declared signed. Previously an unsigned array
    // loaded with signed literals -- in `$signed(a) * rom_hamming[i]`,
    // Verilog treats the WHOLE multiply as unsigned if either operand
    // is unsigned, silently discarding the $signed() cast on the audio
    // sample. Every coefficient here happens to be positive so this
    // was invisible in that direction, but negative (bipolar) audio
    // samples would have been read as huge positive numbers.
    reg signed [15:0] rom_hamming [0:WINDOW_SIZE-1]; 
    initial begin 
        rom_hamming[0]  = 16'sd2621;
        rom_hamming[1]  = 16'sd2696;
        rom_hamming[2]  = 16'sd2920;
        rom_hamming[3]  = 16'sd3291;
        rom_hamming[4]  = 16'sd3805;
        rom_hamming[5]  = 16'sd4457;
        rom_hamming[6]  = 16'sd5241;
        rom_hamming[7]  = 16'sd6148;
        rom_hamming[8]  = 16'sd7170;
        rom_hamming[9]  = 16'sd8297;
        rom_hamming[10] = 16'sd9517;
        rom_hamming[11] = 16'sd10818;
        rom_hamming[12] = 16'sd12188;
        rom_hamming[13] = 16'sd13612;
        rom_hamming[14] = 16'sd15077;
        rom_hamming[15] = 16'sd16568;
        rom_hamming[16] = 16'sd18071;
        rom_hamming[17] = 16'sd19569;
        rom_hamming[18] = 16'sd21049;
        rom_hamming[19] = 16'sd22495;
        rom_hamming[20] = 16'sd23894;
        rom_hamming[21] = 16'sd25231;
        rom_hamming[22] = 16'sd26494;
        rom_hamming[23] = 16'sd27668;
        rom_hamming[24] = 16'sd28744;
        rom_hamming[25] = 16'sd29710;
        rom_hamming[26] = 16'sd30557;
        rom_hamming[27] = 16'sd31275;
        rom_hamming[28] = 16'sd31859;
        rom_hamming[29] = 16'sd32302;
        rom_hamming[30] = 16'sd32600;
        rom_hamming[31] = 16'sd32749;
        rom_hamming[32] = 16'sd32749;
        rom_hamming[33] = 16'sd32600;
        rom_hamming[34] = 16'sd32302;
        rom_hamming[35] = 16'sd31859;
        rom_hamming[36] = 16'sd31275;
        rom_hamming[37] = 16'sd30557;
        rom_hamming[38] = 16'sd29710;
        rom_hamming[39] = 16'sd28744;
        rom_hamming[40] = 16'sd27668;
        rom_hamming[41] = 16'sd26494;
        rom_hamming[42] = 16'sd25231;
        rom_hamming[43] = 16'sd23894;
        rom_hamming[44] = 16'sd22495;
        rom_hamming[45] = 16'sd21049;
        rom_hamming[46] = 16'sd19569;
        rom_hamming[47] = 16'sd18071;
        rom_hamming[48] = 16'sd16568;
        rom_hamming[49] = 16'sd15077;
        rom_hamming[50] = 16'sd13612;
        rom_hamming[51] = 16'sd12188;
        rom_hamming[52] = 16'sd10818;
        rom_hamming[53] = 16'sd9517;
        rom_hamming[54] = 16'sd8297;
        rom_hamming[55] = 16'sd7170;
        rom_hamming[56] = 16'sd6148;
        rom_hamming[57] = 16'sd5241;
        rom_hamming[58] = 16'sd4457;
        rom_hamming[59] = 16'sd3805;
        rom_hamming[60] = 16'sd3291;
        rom_hamming[61] = 16'sd2920;
        rom_hamming[62] = 16'sd2696;
        rom_hamming[63] = 16'sd2621;
    end

    localparam MIDLE          = 2'd0; 
    localparam READ_PREP      = 2'd1; 
    localparam STREAM_WINDOWED = 2'd2; 
    localparam WAIT_BUFFER    = 2'd3; 

    wire mhs = m_axis_tvalid && m_axis_tready;
    reg [1:0] mstate;
    reg [ADDRESS_MEM-1:0] start_ptr; 
    reg [ADDRESS_MEM-1:0] window_counter; 
    wire [ADDRESS_MEM-1:0] read_ptr = start_ptr + window_counter; 

    reg  signed [15:0] dout; 
    wire signed [31:0] windowed_product = $signed(dout) * rom_hamming[window_counter];
    // ^ Declared explicitly as 32 bits. Without this, if the multiply
    // were written inline as `m_axis_tdata <= (a * b) >>> 15`, its
    // width gets context-propagated down from m_axis_tdata (only 16
    // bits) and the product is silently truncated BEFORE the shift
    // ever runs -- the same class of bug as the original missing-
    // rescale issue, just reintroduced via Verilog's implicit width
    // rules instead of an explicit bit-slice. Always give a
    // multiply-then-shift result its own explicitly-sized signal.

    always @(posedge clk) begin 
        if (!rst_n) begin 
            mstate         <= MIDLE; 
            start_ptr      <= {ADDRESS_MEM{1'b0}}; 
            window_counter <= {ADDRESS_MEM{1'b0}}; 
            m_axis_tvalid  <= 0;   
        end
        else begin
            case (mstate) 
                MIDLE: begin 
                    m_axis_tvalid <= 1'b0;
                    if (init_64_point_valid) begin 
                        mstate         <= READ_PREP; 
                        window_counter <= {ADDRESS_MEM{1'b0}}; 
                        start_ptr      <= write_ptr - WINDOW_SIZE[ADDRESS_MEM-1:0]; 
                        dout           <= memory_bank[write_ptr - WINDOW_SIZE[ADDRESS_MEM-1:0]]; 
                    end
                end
                READ_PREP: begin 
                    // FIX (was Bug F): rescale the Q1.15 * Q1.15 = Q2.30
                    // product back down to Q1.15 by taking bits [30:15]
                    // -- the original bug was implicitly taking bits
                    // [15:0] instead (the low 16 bits of the raw
                    // product), which threw away the magnitude entirely
                    // and kept fractional noise.
                    // Plain truncation (no rounding), matching the
                    // truncation already used when the INMP441's 24-bit
                    // samples are cut down to this module's 16-bit
                    // s_axis_tdata -- keeps one consistent bias
                    // convention through the whole signal chain.
                    m_axis_tdata <= windowed_product[30:15]; 
                    m_axis_tvalid <= 1; 
                    mstate <= STREAM_WINDOWED;  
                end 
                STREAM_WINDOWED: begin 
                    if (mhs) begin 
                        // FIX (was Bug C): stop after index 63 (the
                        // 64th sample), not 64 -- the original check
                        // streamed 65 samples and indexed rom_hamming
                        // out of its declared [0:63] range on the last
                        // one.
                        if (window_counter == WINDOW_SIZE-1) begin 
                            window_counter <= 0; 
                            dout           <= memory_bank[read_ptr+1];
                            mstate         <= WAIT_BUFFER; 
                            m_axis_tvalid  <= 0; 
                        end 
                        else begin 
                            mstate         <= READ_PREP;  
                            window_counter <= window_counter + 1'b1; 
                            dout           <= memory_bank[read_ptr+1]; //quick fix  
                            m_axis_tvalid  <= 0; 
                        end
                    end 
                    else begin 
                        // FIX (was Bug A, the critical one): HOLD
                        // TVALID+TDATA while waiting for TREADY.
                        // Previously there was an unconditional
                        // `m_axis_tvalid <= 0;` at the top of this
                        // always block that ran every cycle regardless
                        // of state; with no `else` here, that default
                        // silently withdrew TVALID the instant
                        // TREADY was low even once, and since nothing
                        // else could ever set TVALID back to 1 from
                        // this state, the whole pipeline deadlocked
                        // permanently on the very first stall.
                        m_axis_tvalid <= 1'b1; 
                    end
                end 
                WAIT_BUFFER: begin 
                    if (_32_bit_hop) begin 
                        mstate <= READ_PREP; 
                        // FIX (was Bug D): recompute start_ptr from the
                        // live write_ptr, the same way the very first
                        // window does. The original `start_ptr[5] <=
                        // ~start_ptr[5]` only ever toggles one bit, so
                        // start_ptr could only ever be 0 or 32 -- it
                        // never advanced through the stream, and after
                        // a couple of frames it was reading stale/
                        // overwritten RAM instead of new audio.
                        start_ptr <= write_ptr - WINDOW_SIZE[ADDRESS_MEM-1:0];  
                        dout      <= memory_bank[write_ptr - WINDOW_SIZE[ADDRESS_MEM-1:0]];
   
                    end 
                end 
            endcase
        end
    end

endmodule