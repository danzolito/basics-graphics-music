`include "config.svh"

// Functional check for the Mandelbrot lab: drives the display position so that
// the escape-time engine computes the row y = 0 of the complex plane, then
// checks the RGB output for several known points of the Mandelbrot set.

module tb_check;

    localparam clk_mhz = 50,
               w_key = 8, w_sw = 8, w_led = 8, w_digit = 8, w_gpio = 1,
               screen_width = 640, screen_height = 480,
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
        .w_red         (w_red), .w_green (w_green), .w_blue (w_blue)
    )
    dut (.*);

    always #10 clk = ~ clk;   // 50 MHz

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

    initial
    begin
        #100;
        rst = 0;

        // Move the display to the block row 59 (y = 236). The engine then
        // computes row 60 of the complex plane: cy = 1.5 - 60 * 0.025 = 0.
        y = 236;

        // Wait for the engine to compute all 160 points of that row
        // (worst case 160 * 28 cycles = 89.6 us at 50 MHz).
        #120000;

        // Move the display to row 60: the freshly computed line buffer
        // becomes visible.
        y = 240;
        #200;

        check_pixel (  0, 8'h00, 8'h00, 8'h80);   // c = -2.5: escape time 1
        check_pixel (240, 8'h00, 8'h00, 8'h00);   // c = -1.0: inside, black
        check_pixel (400, 8'h00, 8'h00, 8'h00);   // c =  0.0: inside, black
        check_pixel (520, 8'h00, 8'h40, 8'hFF);   // c =  0.75: escape time 3

        // Pan right (key[2], S6): the view moves right by 20 blocks, so at
        // x = 400 the point becomes c = 0.5, which escapes at iteration 5.
        key [2] = 1;
        #12000000;   // longer than the 10.5 ms key debounce
        key [2] = 0;
        #200;

        y = 236;     // let the engine recompute row 60 with the panned view
        #120000;
        y = 240;
        #200;

        check_pixel (400, 8'h00, 8'hC0, 8'hFF);   // c = 0.5: escape time 5

        // Zoom in (key[0], S8): the iteration limit grows 20 -> 21.
        key [0] = 1;
        #12000000;
        key [0] = 0;
        #200;

        if (led !== 8'd21)
        begin
            $display ("FAIL zoom in: led=%0d, expected 21", led);
            errors++;
        end
        else
            $display ("PASS zoom in: led=%0d", led);

        // Reset (key[6], S2): the iteration limit returns to 20.
        key [6] = 1;
        #12000000;
        key [6] = 0;
        #200;

        if (led !== 8'd20)
        begin
            $display ("FAIL reset: led=%0d, expected 20", led);
            errors++;
        end
        else
            $display ("PASS reset: led=%0d", led);

        if (errors == 0)
            $display ("ALL CHECKS PASSED");
        else
            $display ("%0d CHECKS FAILED", errors);

        $finish;
    end

endmodule
