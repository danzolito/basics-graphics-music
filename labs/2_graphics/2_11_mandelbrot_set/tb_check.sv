`include "config.svh"

// Functional check for the Mandelbrot lab on a 1024x600 screen with
// BLOCK_SIZE = 1: the framebuffer architecture. The engine scans the whole
// image at its own pace and the display always reads the framebuffer. The
// checked pixels lie at y = 300, which the scan reaches after 300 * 1024 +
// 640 = 307840 points, about 307840 * 26 / 64 MHz = 125 ms.

module tb_check;

    localparam clk_mhz = 64,
               w_key = 8, w_sw = 8, w_led = 8, w_digit = 8, w_gpio = 1,
               screen_width = 1024, screen_height = 600,
               w_red = 8, w_green = 8, w_blue = 8,
               w_x = $clog2 (screen_width), w_y = $clog2 (screen_height);

    logic clk = 0, slow_clk = 0, rst = 1;
    logic [w_key   - 1:0] key = '0;
    logic [w_sw    - 1:0] sw  = '0;
    logic [w_led   - 1:0] led;
    logic [        7:0]   abcdefgh;
    logic [w_digit - 1:0] digit;
    logic [w_x     - 1:0] x = '0;
    logic [w_y     - 1:0] y = '0;
    logic [w_red   - 1:0] red, green, blue;
    logic [       23:0]   mic = '0;
    logic [       15:0]   sound;
    logic                 uart_rx = 1'b1, uart_tx;
    wire  [w_gpio  - 1:0] gpio;

    lab_top
    # (
        .clk_mhz       (clk_mhz),
        .w_key         (w_key), .w_sw (w_sw), .w_led (w_led), .w_digit (w_digit), .w_gpio (w_gpio),
        .screen_width  (screen_width), .screen_height (screen_height),
        .w_red         (w_red), .w_green (w_green), .w_blue (w_blue),
        .debounce_depth (4),      // shorten the key debounce for a fast simulation
        .BLOCK_SIZE     (1)       // the maximum resolution: one point per pixel
    )
    dut (.*);

    always #7.8125 clk = ~ clk;   // 64 MHz

    int errors = 0;

    // Wait for the scan to reach the checked row (y = 300) after a restart.

    task automatic wait_row_300 ();
        #130000000;   // 307840 points * 26 cycles = 125 ms at 64 MHz
    endtask

    task automatic check_pixel (input int px, input logic [7:0] exp_r, exp_g, exp_b);
        @ (negedge clk);
        x = px [9:0];
        @ (negedge clk);
        @ (negedge clk);
        @ (negedge clk);
        @ (negedge clk);   // the framebuffer read takes two cycles

        if (red !== exp_r || green !== exp_g || blue !== exp_b)
        begin
            $display ("FAIL x=%0d: got rgb=%02x%02x%02x, expected %02x%02x%02x",
                      px, red, green, blue, exp_r, exp_g, exp_b);
            errors++;
        end
        else
            $display ("PASS x=%0d: rgb=%02x%02x%02x", px, red, green, blue);
    endtask

    // Press a key once and wait for the debounce to both engage and release.

    task automatic press_key (input int k);
        key [k] = 1;
        #2000;   // 2 us = 128 clock cycles at 64 MHz
        key [k] = 0;
        #2000;
    endtask

    // Wait for the units digit of the seven-segment display and check it.

    task automatic check_units (input logic [7:0] exp_seg);
        #20000000;   // let the 120 Hz display update latch the value
        wait (digit [0] == 1'b1);
        @ (negedge clk);

        if (abcdefgh !== exp_seg)
        begin
            $display ("FAIL units digit: got %08b, expected %08b", abcdefgh, exp_seg);
            errors++;
        end
        else
            $display ("PASS units digit: %08b", abcdefgh);
    endtask

    initial
    begin
        #100;
        rst = 0;

        // The display reads row y = 300, where cy = 1.171875 - 300 *
        // 0.00390625 = 0. Wait for the scan to reach that row.
        y = 300;
        wait_row_300 ();

        check_pixel (  0, 8'h00, 8'h00, 8'h80);   // c = -2.5: escape time 1
        check_pixel (640, 8'h00, 8'h00, 8'h00);   // c =  0.0: inside, black
        check_pixel (832, 8'h00, 8'h40, 8'hFF);   // c =  0.75: escape time 3
        check_pixel (836, 8'h00, 8'h40, 8'hFF);   // c =  0.765625: escape time 3

        // Pan right (key[3], S4): the view moves right by 128 points, so at
        // x = 640 the point becomes c = 0.5, which escapes at iteration 5.
        press_key (3);
        wait_row_300 ();

        check_pixel (640, 8'h00, 8'hC0, 8'hFF);   // c = 0.5: escape time 5

        // Zoom in (key[0], S1): from the panned view (-2.0) the point at
        // x = 640 becomes c = 0.35, which escapes at iteration 8, and the
        // iteration limit rises to 25.
        press_key (0);
        wait_row_300 ();

        check_pixel (640, 8'h00, 8'hFF, 8'h80);   // c = 0.35: escape time 8
        check_units (8'b10110110);   // the limit rose to 25 -> units "5"

        // Zoom out (key[1], S2): the view returns exactly to the panned
        // view, so x = 640 shows c = 0.5 again, and the limit is back to 24.
        press_key (1);
        wait_row_300 ();

        check_pixel (640, 8'h00, 8'hC0, 8'hFF);   // c = 0.5: escape time 5

        // The seven-segment display shows the iteration limit.

        check_units (8'b01100110);   // units of 24 = "4"

        if (errors == 0)
            $display ("ALL CHECKS PASSED");
        else
            $display ("%0d CHECKS FAILED", errors);

        $finish;
    end

endmodule
