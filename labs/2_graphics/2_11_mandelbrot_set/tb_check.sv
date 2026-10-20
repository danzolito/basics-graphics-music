`include "config.svh"

// Functional check for the Mandelbrot lab on a 1024x600 screen at a 64 MHz
// lab clock. Drives the display position so that the escape-time engine
// computes the row y = 0 of the complex plane, checks the RGB output for
// several known points of the set, then checks the pan control, the
// seven-segment display of the iteration limit, and the zoom-out floor
// max (1, maxIter - 1).

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
        .debounce_depth (4)   // shorten the key debounce to speed up the simulation
    )
    dut (.*);

    always #7.8125 clk = ~ clk;   // 64 MHz

    int errors = 0;

    task automatic check_pixel (input int px, input logic [7:0] exp_r, exp_g, exp_b);
        @ (negedge clk);
        x = px;
        @ (negedge clk);
        @ (negedge clk);

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
    // The shortened debounce (depth 4 = 16 clock cycles) keeps the simulation
    // fast; the waits here are far longer than needed.

    task automatic press_key (input int k);
        key [k] = 1;
        #2000;   // 2 us = 128 clock cycles at 64 MHz
        key [k] = 0;
        #2000;   // let the debounce release before the next press
    endtask

    // Wait for the units digit of the seven-segment display and check it.

    task automatic check_units (input logic [7:0] exp_seg);
        #20000000;   // let the 120 Hz display update latch the new value
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

        // Move the display to line 299. The engines then compute line 300:
        // cy = 1.171875 - 300 * 0.00390625 = 0.
        y = 299;

        // Wait for the engines to compute all 1024 points of that line
        // (worst case 37 * 33 cycles per engine = 1221 cycles at 50 MHz).
        #120000;

        // Move the display to line 300: the freshly computed line buffer
        // becomes visible. Then wait for the engines to finish the next line
        // they started, so the following line change is caught while idle.
        y = 300;
        #120000;

        check_pixel (  0, 8'h00, 8'h00, 8'h80);   // c = -2.5: escape time 1
        check_pixel (640, 8'h00, 8'h00, 8'h00);   // c =  0.0: inside, black
        check_pixel (832, 8'h00, 8'h40, 8'hFF);   // c =  0.75: escape time 3
        check_pixel (836, 8'h00, 8'h40, 8'hFF);   // c =  0.765625 (the next
                                                  // column of the same engine)

        // Pan right (key[3], S4): the view moves right by 128 points, so at
        // x = 640 the point becomes c = 0.5, which escapes at iteration 5.
        press_key (3);

        // Let the engines finish the line they may still be computing, then
        // recompute line 300 with the panned view.
        #120000;
        y = 299;
        #120000;
        y = 300;
        #120000;

        check_pixel (640, 8'h00, 8'hC0, 8'hFF);   // c = 0.5: escape time 5

        // Zoom in (key[0], S1): the view zooms in around the center. From
        // the panned view (-2.0) the point at x = 640 becomes c = 0.35,
        // which escapes at iteration 8.
        press_key (0);

        #120000;
        y = 299;
        #120000;
        y = 300;
        #120000;

        check_pixel (640, 8'h00, 8'hFF, 8'h80);   // c = 0.35: escape time 8

        // Zoom out (key[1], S2): the view returns exactly to the panned
        // view, so x = 640 shows c = 0.5 again.

        press_key (1);

        #120000;
        y = 299;
        #120000;
        y = 300;
        #120000;

        check_pixel (640, 8'h00, 8'hC0, 8'hFF);   // c = 0.5: escape time 5

        // The iteration limit is fixed: any zooming leaves it at 31.

        check_units (8'b01100000);   // units of 31 = "1"

        repeat (20) press_key (1);   // zoom out to the widest view
        check_units (8'b01100000);   // still 31 = "1"

        press_key (0);               // and zoom back in
        press_key (0);
        check_units (8'b01100000);   // still 31 = "1"

        // Reset (key[6], S7): the initial view and the same limit.

        press_key (6);
        check_units (8'b01100000);   // units of 31 = "1"

        // Scenario: pan left 8 times (view_left clamps at -4), then zoom in
        // 8 times. The zoom center is (-2, 0): the left part of the view
        // (x < -2) lies outside the set and must stay colored, the right
        // part lies inside (black).

        repeat (8) press_key (2);   // S3 - pan left
        repeat (8) press_key (0);   // S1 - zoom in

        #120000;
        y = 299;
        #120000;
        y = 300;
        #120000;

        $display ("SCEN view_left=%0d step=%0d view_top=%0d",
                  dut.view_left, dut.step, dut.view_top);

        begin
            integer px;
            for (px = 0; px < 1024; px = px + 128)
            begin
                @(negedge clk); x = px [9:0]; @(negedge clk); @(negedge clk);
                $display ("SCEN x=%0d rgb=%02x%02x%02x", px, red, green, blue);
            end
        end

        if (errors == 0)
            $display ("ALL CHECKS PASSED");
        else
            $display ("%0d CHECKS FAILED", errors);

        $finish;
    end

endmodule
