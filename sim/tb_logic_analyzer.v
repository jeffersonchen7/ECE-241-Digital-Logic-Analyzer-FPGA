// -----------------------------------------------------------------------------
// tb_logic_analyzer.v
// Self-checking ModelSim testbench for logic_analyzer_core + test_gen.
// Tests:
//   1. 50 MSPS rising-edge trigger on ch0 (10 MHz test signal)
//   2. 10 MSPS masked pattern trigger (ch[5:2] == 4'hA)
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_logic_analyzer;

    reg         clk;
    reg         reset_n;
    wire [7:0]  test_signals;
    reg         arm;
    reg  [2:0]  rate_sel;
    reg  [1:0]  trig_mode;
    reg  [2:0]  trig_ch;
    reg  [7:0]  trig_mask;
    reg  [7:0]  trig_val;
    reg  [12:0] rd_addr;

    wire [7:0]  rd_data;
    wire        trig_fire;
    wire        busy;
    wire        done;
    wire [1:0]  state_dbg;

    integer     errors;
    integer     i;
    reg [12:0]  rd_idx;
    reg [7:0]   curr_sample;

    // 50 MHz clock (20 ns period)
    initial clk = 1'b0;
    always #10 clk = ~clk;

    test_gen u_gen (
        .clk      (clk),
        .reset_n  (reset_n),
        .test_out (test_signals)
    );

    logic_analyzer_core u_dut (
        .clk       (clk),
        .reset_n   (reset_n),
        .probes_in (test_signals),
        .arm       (arm),
        .rate_sel  (rate_sel),
        .trig_mode (trig_mode),
        .trig_ch   (trig_ch),
        .trig_mask (trig_mask),
        .trig_val  (trig_val),
        .rd_addr   (rd_addr),
        .rd_data   (rd_data),
        .trig_fire (trig_fire),
        .busy      (busy),
        .done      (done),
        .state_dbg (state_dbg)
    );

    task read_ram;
        input  [12:0] addr;
        output [7:0]  data_out;
        begin
            @(negedge clk);
            rd_addr = addr;
            @(posedge clk);
            #1;
            data_out = rd_data;
        end
    endtask

    initial begin
        errors    = 0;
        reset_n   = 1'b0;
        arm       = 1'b0;
        rate_sel  = 3'd0; // 50 MSPS
        trig_mode = 2'd0; // rising edge
        trig_ch   = 3'd0; // ch0 (10 MHz wave)
        trig_mask = 8'h00;
        trig_val  = 8'h00;
        rd_addr   = 13'd0;

        repeat (5) @(posedge clk);
        reset_n = 1'b1;
        repeat (5) @(posedge clk);

        // TEST 1: 50 MSPS, rising edge on ch0
        $display("=== TEST 1: 50 MSPS, rising edge on ch0 ===");
        @(negedge clk); arm = 1'b1;
        @(negedge clk); arm = 1'b0;

        wait (done == 1'b1);
        @(posedge clk);

        read_ram(13'd0, curr_sample);
        if (curr_sample[0] !== 1'b1) begin
            $display("ERROR Test 1: mem[0][0] should be 1 on rising trigger, got %b", curr_sample[0]);
            errors = errors + 1;
        end
        for (i = 0; i < 10; i = i + 1) begin
            rd_idx = i;
            read_ram(rd_idx, curr_sample);
            $display("  mem[%0d] = %b (ch0=%b)", i, curr_sample, curr_sample[0]);
        end

        // TEST 2: 10 MSPS, masked pattern trigger (ch5:2 == 4'hA)
        $display("=== TEST 2: 10 MSPS, pattern ch[5:2]=4'hA ===");
        @(negedge clk);
        rate_sel  = 3'd2; // 10 MSPS (div by 5)
        trig_mode = 2'd3; // pattern trigger
        trig_mask = 8'b0011_1100;
        trig_val  = 8'b0010_1000;

        @(negedge clk); arm = 1'b1;
        @(negedge clk); arm = 1'b0;

        wait (done == 1'b0);
        wait (done == 1'b1);
        @(posedge clk);

        read_ram(13'd0, curr_sample);
        if ((curr_sample & trig_mask) !== (trig_val & trig_mask)) begin
            $display("ERROR Test 2: mem[0]=%b did not match pattern!", curr_sample);
            errors = errors + 1;
        end

        if (errors == 0)
            $display("ALL TESTS PASSED!");
        else
            $display("FAILED with %0d errors.", errors);

        $stop;
    end

endmodule
