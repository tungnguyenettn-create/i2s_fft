module fifo #(
    parameter DEPTH = 8,
    parameter WIDTH = 16
)
(
    input  rst_n, clk, wr_en, rd_en,

    input  [WIDTH-1:0]      din,
    output reg [WIDTH-1:0]  dout,
    output empty, full
);
    reg [$clog2(DEPTH)-1:0] wr_ptr;
    reg [$clog2(DEPTH)-1:0] rd_ptr;
    reg [WIDTH-1:0]         fifo [0:DEPTH-1];

    always @(posedge clk) begin
        if (!rst_n) begin
            wr_ptr <= 0;
        end else begin
            if (wr_en & !full) begin
                fifo[wr_ptr] <= din;
                wr_ptr       <= wr_ptr + 1'b1;
            end
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            rd_ptr <= 0;
        end else begin
            if (rd_en & !empty) begin
                dout   <= fifo[rd_ptr];
                rd_ptr <= rd_ptr + 1'b1;
            end
        end
    end

    assign full  = ((wr_ptr + 1'b1) == rd_ptr);
    assign empty = (wr_ptr == rd_ptr);
endmodule