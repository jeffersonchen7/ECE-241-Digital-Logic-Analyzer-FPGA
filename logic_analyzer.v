module top (CLOCK_50, KEY, SW, LEDR, GPIO_0, GPIO_1);
    input CLOCK_50;
    input [3:0] KEY;
    input [9:0] SW;
    input [35:0] GPIO_0;
    output [9:0] LEDR;
    output [35:0] GPIO_1;

    wire [7:0] test_out;
    reg [7:0] probes;
    reg [2:0] rate_sel;
    reg arm_sig;
    wire live_refresh;
    wire [12:0] rd_addr;
    wire [7:0] rd_data;
    wire trig_fire, busy, done;
    wire [1:0] state_dbg;

    always @(*) begin
        if (SW[9]) // sample type 
            probes = test_out;
        else
            probes = GPIO_0[7:0];

        if (SW[8]) // select sample rate
            rate_sel = 3'd2;
        else
            rate_sel = 3'd0;

        if (SW[7]) // live or snapshot viewing
            arm_sig = live_refresh;
        else
            arm_sig = ~KEY[1];
    end

    assign GPIO_1[35:8] = 28'd0;
    assign GPIO_1[7:0]  = test_out;

    assign LEDR[7:0] = rd_data;
    assign LEDR[8] = busy; // still filling
    assign LEDR[9] = done; // done filling

    assign rd_addr[12:7] = 6'd0;
    assign rd_addr[6:0]  = SW[6:0];

    test_gen u_gen (CLOCK_50, KEY[0], test_out);
    live_timer u_live (CLOCK_50, KEY[0], SW[7], live_refresh);

    logic_analyzer_core u_core (
        CLOCK_50, KEY[0], probes, arm_sig, rate_sel,
        2'd0, // rising edge on ch0
        3'd0, 8'd0, 8'd0, rd_addr, rd_data,
        trig_fire, busy, done, state_dbg
    );
endmodule


module logic_analyzer_core (
    clk, reset_n, probes_in, arm, rate_sel, trig_mode, trig_ch,
    trig_mask, trig_val, rd_addr, rd_data, trig_fire, busy, done, state_dbg
);
    input clk, reset_n, arm;
    input [7:0] probes_in, trig_mask, trig_val; // pattern trigger channels, values for those channels to trigger
    input [1:0] trig_mode;
    input [2:0] rate_sel, trig_ch;  
    input [12:0] rd_addr;

    output [7:0] rd_data;
    output trig_fire, busy, done;
    output [1:0] state_dbg; // tracks fsm state

    wire sample_en;
    wire [7:0] synced_sample;
    wire wr_en;
    wire [12:0] wr_addr;

    rate_divider u_rate_div (clk, reset_n, rate_sel, sample_en);
    sync_2ff u_sync (clk, reset_n, probes_in, synced_sample);
    trigger_unit u_trig (clk, reset_n, sample_en, synced_sample, trig_mode, trig_ch, trig_mask, trig_val, trig_fire);
    capture_fsm u_cap_fsm (clk, reset_n, arm, sample_en, trig_fire, wr_en, wr_addr, busy, done, state_dbg);
    ram_8kx8 u_ram (clk, wr_en, wr_addr, synced_sample, rd_addr, rd_data);
endmodule


module rate_divider (clk, reset_n, rate_sel, sample_en);
    input clk, reset_n;
    input [2:0] rate_sel;
    output sample_en;

    reg [12:0] div_max;
    reg [12:0] cnt;

    always @(*) begin
        case (rate_sel)
            3'd0: div_max = 13'd1;    // 50 MSPS
            3'd1: div_max = 13'd2;    // 25 MSPS
            3'd2: div_max = 13'd5;    // 10 MSPS
            3'd3: div_max = 13'd10;   // 5 MSPS
            3'd4: div_max = 13'd50;   // 1 MSPS
            3'd5: div_max = 13'd100;  // 500 kSPS (matches LTC2308 ADC)
            3'd6: div_max = 13'd500;  // 100 kSPS
            3'd7: div_max = 13'd5000; // 10 kSPS
            default: div_max = 13'd1;
        endcase
    end

    assign sample_en = (cnt >= div_max - 13'd1);

    always @(posedge clk) begin
        if (!reset_n)
            cnt <= 13'd0;
        else if (sample_en)
            cnt <= 13'd0;
        else
            cnt <= cnt + 13'd1;
    end
endmodule


module sync_2ff (clk, reset_n, async_in, sync_out);
    input clk, reset_n;
    input [7:0] async_in;
    output [7:0] sync_out;

    reg [7:0] stage1;
    reg [7:0] sync_out;

    always @(posedge clk) begin
        if (!reset_n) begin
            stage1 <= 8'd0;
            sync_out <= 8'd0;
        end else begin
            stage1 <= async_in;
            sync_out <= stage1;
        end
    end
endmodule


module trigger_unit (clk, reset_n, sample_en, sample, trig_mode, trig_ch, trig_mask, trig_val, trig_fire);
    input clk, reset_n, sample_en;
    input [7:0] sample, trig_mask, trig_val;
    input [1:0] trig_mode;
    input [2:0] trig_ch;
    output trig_fire;

    reg trig_fire;
    reg [7:0] prev_sample;
    wire curr_bit = sample[trig_ch];
    wire prev_bit = prev_sample[trig_ch];

    always @(posedge clk) begin
        if (!reset_n)
            prev_sample <= 8'd0;
        else if (sample_en)
            prev_sample <= sample;
    end

    always @(*) begin
        case (trig_mode)
            2'b00: trig_fire = curr_bit & ~prev_bit;                             // rising edge
            2'b01: trig_fire = ~curr_bit & prev_bit;                             // falling edge
            2'b10: trig_fire = curr_bit ^ prev_bit;                              // either edge
            2'b11: trig_fire = ((sample & trig_mask) == (trig_val & trig_mask)); // pattern
            default: trig_fire = 1'b0;
        endcase
    end
endmodule


module capture_fsm (clk, reset_n, arm, sample_en, trig_fire, wr_en, wr_addr, busy, done, state_dbg);
    input clk, reset_n, arm, sample_en, trig_fire;
    output wr_en, busy, done;
    output [12:0] wr_addr;
    output [1:0] state_dbg;

    reg wr_en;
    reg [12:0] wr_addr;

    parameter S_IDLE      = 2'd0,
              S_WAIT_TRIG = 2'd1,
              S_CAPTURE   = 2'd2,
              S_DONE      = 2'd3;

    reg [1:0] y_Q, Y_D;
    reg arm_prev;
    wire arm_pulse = arm & ~arm_prev;

    assign busy = (y_Q == S_WAIT_TRIG) || (y_Q == S_CAPTURE);
    assign done = (y_Q == S_DONE);
    assign state_dbg = y_Q;

    always @(*) begin
        Y_D = y_Q;
        wr_en = 1'b0;

        case (y_Q)
            S_IDLE: begin
                if (arm_pulse)
                    Y_D = S_WAIT_TRIG;
            end

            S_WAIT_TRIG: begin
                if (sample_en && trig_fire) begin
                    wr_en = 1'b1;
                    Y_D = S_CAPTURE;
                end
            end

            S_CAPTURE: begin
                if (sample_en) begin
                    wr_en = 1'b1;
                    if (wr_addr == 13'd8191)
                        Y_D = S_DONE;
                end
            end

            S_DONE: begin
                if (arm_pulse)
                    Y_D = S_WAIT_TRIG;
            end

            default: Y_D = S_IDLE;
        endcase
    end

    always @(posedge clk) begin
        if (!reset_n) begin
            y_Q <= S_IDLE;
            arm_prev <= 1'b0;
            wr_addr <= 13'd0;
        end else begin
            y_Q <= Y_D;
            arm_prev <= arm;

            if ((y_Q == S_IDLE || y_Q == S_DONE) && arm_pulse)
                wr_addr <= 13'd0;
            else if (sample_en && wr_en)
                wr_addr <= wr_addr + 13'd1;
        end
    end
endmodule


module ram_8kx8 (clk, wr_en, wr_addr, wr_data, rd_addr, rd_data);
    input clk, wr_en;
    input [12:0] wr_addr, rd_addr;
    input [7:0] wr_data;
    output [7:0] rd_data;

    reg [7:0] rd_data;
    reg [7:0] mem [0:8191];

    always @(posedge clk) begin
        if (wr_en)
            mem[wr_addr] <= wr_data;
        rd_data <= mem[rd_addr];
    end
endmodule


module test_gen (clk, reset_n, test_out);
    input clk, reset_n;
    output [7:0] test_out;

    reg [2:0] mod5_cnt;
    reg [3:0] mod10_cnt;
    reg [5:0] free_cnt;

    always @(posedge clk) begin
        if (!reset_n) begin
            mod5_cnt <= 3'd0;
            mod10_cnt <= 4'd0;
            free_cnt <= 6'd0;
        end else begin
            if (mod5_cnt == 3'd4)
                mod5_cnt <= 3'd0;
            else
                mod5_cnt <= mod5_cnt + 3'd1;

            if (mod10_cnt == 4'd9)
                mod10_cnt <= 4'd0;
            else
                mod10_cnt <= mod10_cnt + 4'd1;

            free_cnt <= free_cnt + 6'd1;
        end
    end

    assign test_out[0] = (mod5_cnt < 3'd2);     // 10 MHz
    assign test_out[1] = (mod10_cnt < 4'd5);    // 5 MHz
    assign test_out[5:2] = free_cnt[5:2];       // 4 bit counter
    assign test_out[6] = (free_cnt == 6'd15);   // periodic pulse
    assign test_out[7] = free_cnt[5];           // approx a 781 kHz square wave
endmodule


module live_timer (clk, reset_n, enable, refresh_pulse);
    input clk, reset_n, enable;
    output refresh_pulse;

    reg refresh_pulse;
    reg [19:0] cnt;
    reg enable_prev;

    // 833,333 ticks at 50 MHz = ~60 Hz live refresh rate
    parameter REFRESH_TICKS = 20'd833333;

    always @(posedge clk) begin
        if (!reset_n) begin
            cnt <= 20'd0;
            enable_prev <= 1'b0;
            refresh_pulse <= 1'b0;
        end else begin
            enable_prev <= enable;
            refresh_pulse <= 1'b0;

            if (!enable) begin
                cnt <= 20'd0;
            end else if (!enable_prev || (cnt >= REFRESH_TICKS - 20'd1)) begin
                cnt <= 20'd0;
                refresh_pulse <= 1'b1;
            end else begin
                cnt <= cnt + 20'd1;
            end
        end
    end
endmodule
