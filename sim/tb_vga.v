`timescale 1ns/1ps

module tb_vga;

    reg         CLOCK_50;
    reg  [3:0]  KEY;
    reg  [9:0]  SW;
    reg  [35:0] GPIO_0;

    wire [9:0]  LEDR;
    wire [35:0] GPIO_1;
    wire [7:0]  VGA_R, VGA_G, VGA_B;
    wire        VGA_HS, VGA_VS, VGA_CLK, VGA_BLANK_N, VGA_SYNC_N;

    integer errors;
    integer px;
    integer hs_low_cnt, vs_low_cnt, vis_cnt;
    integer ax, ay;

    initial CLOCK_50 = 1'b0;
    always #10 CLOCK_50 = ~CLOCK_50;

    top u_dut (
        .CLOCK_50    (CLOCK_50),
        .KEY         (KEY),
        .SW          (SW),
        .LEDR        (LEDR),
        .GPIO_0      (GPIO_0),
        .GPIO_1      (GPIO_1),
        .VGA_R       (VGA_R),
        .VGA_G       (VGA_G),
        .VGA_B       (VGA_B),
        .VGA_HS      (VGA_HS),
        .VGA_VS      (VGA_VS),
        .VGA_CLK     (VGA_CLK),
        .VGA_BLANK_N (VGA_BLANK_N),
        .VGA_SYNC_N  (VGA_SYNC_N)
    );

    initial begin
        errors = 0;
        KEY    = 4'b1111;
        SW     = 10'b1000000000; // SW[9]=1 (test_gen), SW[8]=0 (50 MSPS), SW[7]=0 (snapshot), 1x zoom, pan 0
        GPIO_0 = 36'd0;

        // Reset pulse on KEY[0]
        KEY[0] = 1'b0;
        repeat (6) @(posedge CLOCK_50);
        KEY[0] = 1'b1;
        repeat (6) @(posedge CLOCK_50);

        // Press KEY[1] to arm snapshot capture
        @(negedge CLOCK_50);
        KEY[1] = 1'b0;
        repeat (4) @(posedge CLOCK_50);
        @(negedge CLOCK_50);
        KEY[1] = 1'b1;

        // Wait until done (LEDR[9]) turns high
        wait (LEDR[9] == 1'b1);
        $display("Capture done (LEDR[9]=1). Waiting for full VGA frame...");

        // Align to start of line 492 right after vertical sync pulse ends
        @(negedge VGA_VS);
        @(posedge VGA_VS);

        hs_low_cnt = 0;
        vs_low_cnt = 0;
        vis_cnt    = 0;

        // Scan 1 full frame = 800 * 525 = 420,000 VGA_CLK ticks
        for (px = 0; px < 420000; px = px + 1) begin
            @(posedge VGA_CLK);
            if (VGA_HS == 1'b0) hs_low_cnt = hs_low_cnt + 1;
            if (VGA_VS == 1'b0) vs_low_cnt = vs_low_cnt + 1;

            if (VGA_BLANK_N == 1'b0) begin
                if (VGA_R !== 8'd0 || VGA_G !== 8'd0 || VGA_B !== 8'd0) begin
                    if (errors < 10)
                        $display("ERROR: Non-zero RGB (%0d,%0d,%0d) during blanking at px=%0d", VGA_R, VGA_G, VGA_B, px);
                    errors = errors + 1;
                end
            end else begin
                ax = vis_cnt % 640;
                ay = vis_cnt / 640;

                // Status badge (done=1 -> green)
                if (ax == 16 && ay == 8) begin
                    if (VGA_R !== 8'd40 || VGA_G !== 8'd220 || VGA_B !== 8'd90) begin
                        $display("ERROR: Status box expected (40,220,90), got (%0d,%0d,%0d)", VGA_R, VGA_G, VGA_B);
                        errors = errors + 1;
                    end
                end

                // Divider bar
                if (ax == 100 && ay == 272) begin
                    if (VGA_R !== 8'd70 || VGA_G !== 8'd140 || VGA_B !== 8'd190) begin
                        $display("ERROR: Divider bar expected (70,140,190), got (%0d,%0d,%0d)", VGA_R, VGA_G, VGA_B);
                        errors = errors + 1;
                    end
                end

                // ch0 waveform checks (1,1,0,0,0,1 starting at trigger x=0; ch0 lane y=16..47 -> high=22, low=40)
                if (ay == 22 && (ax == 0 || ax == 2 || ax == 5)) begin
                    if (VGA_R !== 8'd0 || VGA_G !== 8'd255 || VGA_B !== 8'd140) begin
                        $display("ERROR: ch0 high/edge expected at x=%0d y=22, got (%0d,%0d,%0d)", ax, VGA_R, VGA_G, VGA_B);
                        errors = errors + 1;
                    end
                end
                if (ay == 22 && ax == 3) begin
                    if (VGA_G == 8'd255) begin
                        $display("ERROR: ch0 should be low at x=3 y=22");
                        errors = errors + 1;
                    end
                end
                if (ay == 40 && ax == 3) begin
                    if (VGA_R !== 8'd0 || VGA_G !== 8'd255 || VGA_B !== 8'd140) begin
                        $display("ERROR: ch0 low rail expected at x=3 y=40, got (%0d,%0d,%0d)", ax, VGA_R, VGA_G, VGA_B);
                        errors = errors + 1;
                    end
                end

                vis_cnt = vis_cnt + 1;
            end
        end

        if (hs_low_cnt !== 50400) begin
            $display("ERROR: hs_low_cnt=%0d, expected 50400 (96*525)", hs_low_cnt);
            errors = errors + 1;
        end
        if (vs_low_cnt !== 1600) begin
            $display("ERROR: vs_low_cnt=%0d, expected 1600 (2*800)", vs_low_cnt);
            errors = errors + 1;
        end
        if (vis_cnt !== 307200) begin
            $display("ERROR: vis_cnt=%0d, expected 307200 (640*480)", vis_cnt);
            errors = errors + 1;
        end

        if (errors == 0)
            $display("ALL VGA TESTS PASSED! (640x480 visible=%0d, HS=%0d, VS=%0d)", vis_cnt, hs_low_cnt, vs_low_cnt);
        else
            $display("VGA TEST FAILED with %0d errors.", errors);

        $stop;
    end

endmodule
