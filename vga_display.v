module vga_timing (
    clk, reset_n, pix_en, h_cnt, v_cnt, visible,
    vga_clk, vga_hs, vga_vs, vga_blank_n, vga_sync_n
);
    input clk, reset_n;
    output pix_en;
    output [9:0] h_cnt, v_cnt;
    output visible;
    output vga_clk, vga_hs, vga_vs, vga_blank_n, vga_sync_n;

    reg vga_clk;
    reg [9:0] h_cnt, v_cnt;
    reg vga_hs, vga_vs, vga_blank_n;

    // 640x480 @ 60 Hz constants
    parameter H_VIS   = 10'd640,
              H_FRONT = 10'd16,
              H_SYNC  = 10'd96,
              H_TOTAL = 10'd800;

    parameter V_VIS   = 10'd480,
              V_FRONT = 10'd10,
              V_SYNC  = 10'd2,
              V_TOTAL = 10'd525;

    // step on falling edge of 25 MHz clk
    assign pix_en = vga_clk;
    assign visible = (h_cnt < H_VIS) && (v_cnt < V_VIS);
    assign vga_sync_n = 1'b0;

    always @(posedge clk) begin
        if (!reset_n) begin
            vga_clk <= 1'b0;
            h_cnt <= 10'd0;
            v_cnt <= 10'd0;
            vga_hs <= 1'b1;
            vga_vs <= 1'b1;
            vga_blank_n <= 1'b0;
        end else begin
            vga_clk <= ~vga_clk;

            if (pix_en) begin
                if ((h_cnt >= H_VIS + H_FRONT) && (h_cnt < H_VIS + H_FRONT + H_SYNC))
                    vga_hs <= 1'b0;
                else
                    vga_hs <= 1'b1;

                if ((v_cnt >= V_VIS + V_FRONT) && (v_cnt < V_VIS + V_FRONT + V_SYNC))
                    vga_vs <= 1'b0;
                else
                    vga_vs <= 1'b1;

                vga_blank_n <= visible;

                if (h_cnt == H_TOTAL - 10'd1) begin
                    h_cnt <= 10'd0;
                    if (v_cnt == V_TOTAL - 10'd1)
                        v_cnt <= 10'd0;
                    else
                        v_cnt <= v_cnt + 10'd1;
                end else begin
                    h_cnt <= h_cnt + 10'd1;
                end
            end
        end
    end
endmodule


module vga_renderer (
    clk, reset_n, pix_en, h_cnt, v_cnt, visible,
    rd_data, pan_sel, zoom_sel, busy_flag, done_flag,
    rd_addr, vga_r, vga_g, vga_b
);
    input clk, reset_n, pix_en, visible;
    input [9:0] h_cnt, v_cnt;
    input [7:0] rd_data;
    input [4:0] pan_sel;
    input [1:0] zoom_sel;
    input busy_flag, done_flag;

    output [12:0] rd_addr;
    output [7:0] vga_r, vga_g, vga_b;

    reg [12:0] rd_addr;
    reg [7:0] vga_r, vga_g, vga_b;
    reg [7:0] prev_sample;

    reg [12:0] pan_offset;
    reg [9:0] x_scaled;
    reg [12:0] x_ext;

    reg in_digital;
    reg [9:0] y_dig;
    reg [2:0] ch;
    reg [4:0] ly;
    reg curr_bit, prev_bit;
    reg wave_hit;

    reg [7:0] next_r, next_g, next_b;

    always @(*) begin
        // pan in 128-sample steps + zoom
        pan_offset = 13'd0;
        pan_offset[11:7] = pan_sel;

        case (zoom_sel)
            2'd0: x_scaled = h_cnt;
            2'd1: x_scaled = h_cnt >> 1;
            2'd2: x_scaled = h_cnt >> 2;
            2'd3: x_scaled = h_cnt >> 3;
            default: x_scaled = h_cnt;
        endcase

        x_ext = 13'd0;
        x_ext[9:0] = x_scaled;

        if (h_cnt < 10'd640)
            rd_addr = pan_offset + x_ext;
        else
            rd_addr = pan_offset;

        // 8 digital lanes in top half (y = 16..271)
        if ((v_cnt >= 10'd16) && (v_cnt < 10'd272)) begin
            in_digital = 1'b1;
            y_dig = v_cnt - 10'd16;
        end else begin
            in_digital = 1'b0;
            y_dig = 10'd0;
        end

        ch = y_dig[7:5];
        ly = y_dig[4:0];
        curr_bit = rd_data[ch];
        prev_bit = prev_sample[ch];

        // high, low, or vertical edge
        wave_hit = 1'b0;
        if (in_digital) begin
            if (curr_bit && ((ly == 5'd6) || (ly == 5'd7)))
                wave_hit = 1'b1;
            else if (!curr_bit && ((ly == 5'd24) || (ly == 5'd25)))
                wave_hit = 1'b1;
            else if ((h_cnt > 10'd0) && (curr_bit != prev_bit) && (ly >= 5'd6) && (ly <= 5'd25))
                wave_hit = 1'b1;
        end

        next_r = 8'd0;
        next_g = 8'd0;
        next_b = 8'd0;

        if (visible) begin
            if (wave_hit) begin
                case (ch)
                    3'd0: begin next_r = 8'd0;   next_g = 8'd255; next_b = 8'd140; end
                    3'd1: begin next_r = 8'd0;   next_g = 8'd210; next_b = 8'd255; end
                    3'd2: begin next_r = 8'd255; next_g = 8'd220; next_b = 8'd60;  end
                    3'd3: begin next_r = 8'd255; next_g = 8'd140; next_b = 8'd40;  end
                    3'd4: begin next_r = 8'd220; next_g = 8'd120; next_b = 8'd255; end
                    3'd5: begin next_r = 8'd100; next_g = 8'd180; next_b = 8'd255; end
                    3'd6: begin next_r = 8'd255; next_g = 8'd90;  next_b = 8'd140; end
                    3'd7: begin next_r = 8'd180; next_g = 8'd255; next_b = 8'd90;  end
                    default: begin next_r = 8'd255; next_g = 8'd255; next_b = 8'd255; end
                endcase
            end else if ((v_cnt >= 10'd4) && (v_cnt < 10'd12) && (h_cnt >= 10'd12) && (h_cnt < 10'd28)) begin
                if (done_flag) begin
                    next_r = 8'd40; next_g = 8'd220; next_b = 8'd90;
                end else if (busy_flag) begin
                    next_r = 8'd240; next_g = 8'd170; next_b = 8'd30;
                end else begin
                    next_r = 8'd70; next_g = 8'd80; next_b = 8'd95;
                end
            end else if ((v_cnt == 10'd272) || (v_cnt == 10'd273)) begin
                next_r = 8'd70; next_g = 8'd140; next_b = 8'd190;
            end else if (in_digital && (ly == 5'd0)) begin
                next_r = 8'd28; next_g = 8'd36; next_b = 8'd50;
            end else if ((h_cnt == 10'd0) && (pan_sel == 5'd0) && in_digital) begin
                next_r = 8'd170; next_g = 8'd55; next_b = 8'd55;
            end else if (h_cnt[5:0] == 6'd0) begin
                next_r = 8'd28; next_g = 8'd36; next_b = 8'd50;
            end else if (v_cnt == 10'd376) begin
                next_r = 8'd28; next_g = 8'd36; next_b = 8'd50;
            end else begin
                next_r = 8'd10; next_g = 8'd14; next_b = 8'd22;
            end
        end
    end

    always @(posedge clk) begin
        if (!reset_n) begin
            prev_sample <= 8'd0;
            vga_r <= 8'd0;
            vga_g <= 8'd0;
            vga_b <= 8'd0;
        end else if (pix_en) begin
            prev_sample <= rd_data;
            vga_r <= next_r;
            vga_g <= next_g;
            vga_b <= next_b;
        end
    end
endmodule
