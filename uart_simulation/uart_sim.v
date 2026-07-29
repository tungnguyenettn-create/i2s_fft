`timescale 1ns/1ps

module uart_sim #(
    parameter uart_cycle   = 333.33,
    parameter sample_cycle = 23000
);
    reg clk;
    reg rst_n;
    reg rx_data;
    wire tx_serial;

    uart_check checker_uart0(
        .clk(clk),
        .rst_n(rst_n),
        .rx_data(rx_data),
        .tx_serial(tx_serial)
    );

    initial begin
        clk = 0;
        forever #18.5185 clk = ~clk;
    end

    initial begin
        rst_n = 0;
        #50 rst_n = 1;
    end

    integer i;
    reg [7:0] index;
    initial begin
        rx_data = 1'b1;
        #150;
        for (i = 0; i < 255; i = i + 1) begin
            index = i;
            #uart_cycle rx_data = 1'b0; // start bit
            #uart_cycle rx_data = index[0];
            #uart_cycle rx_data = index[1];
            #uart_cycle rx_data = index[2];
            #uart_cycle rx_data = index[3];
            #uart_cycle rx_data = index[4];
            #uart_cycle rx_data = index[5];
            #uart_cycle rx_data = index[6];
            #uart_cycle rx_data = index[7];
            #uart_cycle rx_data = 1'b1;   // stop bit
        end
    end

    initial begin
        $dumpfile("uart_sim.vcd");
        $dumpvars(0, uart_sim);
    end

    // ---- RX-side visibility (unchanged from your version) ----
    wire rx_valid = checker_uart0.rx_valid;
    wire tx_ready  = checker_uart0.tx_ready;
    wire [15:0] audio_data = checker_uart0.audio_data;

    // ---- NEW: expose FIFO status inside axi_uart_rx, to confirm/rule out overflow ----
    wire fifo_full  = checker_uart0.uart_rx.full;
    wire fifo_empty = checker_uart0.uart_rx.empty;

    // ---- NEW: scoreboard for RX side -- what SHOULD audio_data be? ----
    // Since your ASSEMBLE state packs high-byte-first ({audio_data[7:0], byte_data}),
    // sample n's expected value is {2n, 2n+1} for n = 0,1,2...
    integer rx_expect_count;
    reg [15:0] rx_expected;
    initial rx_expect_count = 0;
    reg [7:0] rx_expect_hi, rx_expect_lo;
    initial begin
        forever begin
            @(posedge clk);
            if (rx_valid && tx_ready) begin
                rx_expect_hi = rx_expect_count[7:0]*2;
                rx_expect_lo = rx_expect_count[7:0]*2 + 1;
                rx_expected  = {rx_expect_hi, rx_expect_lo};
                if (audio_data !== rx_expected) begin
                    $display("[RX MISMATCH] t=%0t expected=%h got=%h (fifo_full=%b fifo_empty=%b)",
                              $time, rx_expected, audio_data, fifo_full, fifo_empty);
                end else begin
                    $display("[RX OK]       t=%0t audio_data=%h (fifo_full=%b)",
                              $time, audio_data, fifo_full);
                end
                rx_expect_count = rx_expect_count + 1;
            end
        end
    end

    // ---- TX-side loopback checker (unchanged structurally from your version) ----
    wire tx_serial1;
    uart_check checker_uart1(
        .clk(clk),
        .rst_n(rst_n),
        .rx_data(tx_serial),
        .tx_serial(tx_serial1)
    );

    wire rx_valid1  = checker_uart1.rx_valid;
    wire tx_ready1  = checker_uart1.tx_ready;
    wire [15:0] audio_data1 = checker_uart1.audio_data;
    wire fifo_full1  = checker_uart1.uart_rx.full;
    wire fifo_empty1 = checker_uart1.uart_rx.empty;

    // ---- NEW: scoreboard for the TX-side loopback, same expected sequence ----
    integer tx_expect_count;
    reg [15:0] tx_expected;
    initial tx_expect_count = 0;

    reg [7:0] tx_expect_hi, tx_expect_lo;
    initial begin
        forever begin
            @(posedge clk);
            if (rx_valid1 && tx_ready1) begin
                tx_expect_hi = tx_expect_count[7:0]*2;
                tx_expect_lo = tx_expect_count[7:0]*2 + 1;
                tx_expected  = {tx_expect_hi, tx_expect_lo};
                if (audio_data1 !== tx_expected) begin
                    $display("[TX MISMATCH] t=%0t expected=%h got=%h (fifo_full=%b fifo_empty=%b)",
                              $time, tx_expected, audio_data1, fifo_full1, fifo_empty1);
                end else begin
                    $display("[TX OK]       t=%0t audio_data=%h (fifo_full=%b)",
                              $time, audio_data1, fifo_full1);
                end
                tx_expect_count = tx_expect_count + 1;
            end
        end
    end

    initial begin
        #100000000;   // generous margin -- adjust if 255 samples need more/less time
        $finish;
    end

endmodule