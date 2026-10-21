`include "config.svh"

// Interactive Mandelbrot set.
//
// The complex plane is shown on the screen. The image is computed by a
// sequential escape-time engine and kept in a persistent framebuffer: the
// display always reads the framebuffer at the full frame rate, while the
// engine updates the blocks one by one as the computation progresses.
//
// The block size only trades the picture resolution against the refresh
// time of the image: with MAX_ITER = 24, BLOCK_SIZE = 4 refreshes the whole
// picture in about 17 ms and BLOCK_SIZE = 1 in about 320 ms. The display
// itself never breaks and the frame rate never changes - during a recompute
// the previous image is shown and is progressively replaced from the top.
// Every key press restarts the computation with the new view.
//
// The board runs the lab on the 50 MHz pixel clock of the 1024x600 video
// mode, so the lab and the display share one clock domain and every path
// from the pixel coordinates to the RGB output has a full 20 ns pixel
// period.
//
// The view keeps square cells of the complex plane, so the picture is not
// distorted on any screen: the initial view spans [-2.5, 1.5] horizontally,
// and its height follows the screen aspect ratio.
//
// The coordinates are fixed point Q4.24 (28 bits). The 28x28 multipliers fit
// into two cascaded DSPs instead of four, and the zoom update is split into
// two stages, so every combinational path meets the 50 MHz period with
// margin.
//
// Controls (direct order: the driver maps S1 -> key[0], S2 -> key[1], ...):
//   key[0] (S1) - zoom in      (MATLAB reference: Q)
//   key[1] (S2) - zoom out     (MATLAB reference: E)
//   key[2] (S3) - pan left    (MATLAB reference: A)
//   key[3] (S4) - pan right     (MATLAB reference: D)
//   key[4] (S5) - pan up       (MATLAB reference: W)
//   key[5] (S6) - pan down     (MATLAB reference: S)
//   key[6] (S7) - reset the view
//   key[7] (S8) - reset the view (spare)
//
// The iteration limit follows the zoom level: zooming in increments ZOOM_LVL
// and zooming out decrements it, and the engine iterates
// MAX_ITER = max (1, min (31, ZOOM_LVL)) times per point. The limit is shown
// on the TM1638 module's seven-segment display (the two rightmost digits).

module lab_top
# (
    parameter  clk_mhz       = 50,
               w_key         = 4,
               w_sw          = 8,
               w_led         = 8,
               w_digit       = 8,
               w_gpio        = 100,

               screen_width  = 640,
               screen_height = 480,

               w_red         = 4,
               w_green       = 4,
               w_blue        = 4,

               w_x           = $clog2 ( screen_width  ),
               w_y           = $clog2 ( screen_height ),

               // Debounce depth of the keys, in bits (2^depth clock cycles).
               // The testbench shortens it to speed up the simulation.

               debounce_depth = 19,

               // One Mandelbrot point per BLOCK_SIZE x BLOCK_SIZE pixel
               // block. Smaller blocks give a finer picture and
               // proportionally longer image refresh time; the display rate
               // never changes.

               BLOCK_SIZE     = 1
)
(
    input                        clk,
    input                        slow_clk,
    input                        rst,

    // Keys, switches, LEDs

    input        [w_key   - 1:0] key,
    input        [w_sw    - 1:0] sw,
    output logic [w_led   - 1:0] led,

    // A dynamic seven-segment display

    output logic [          7:0] abcdefgh,
    output logic [w_digit - 1:0] digit,

    // Graphics

    input        [w_x     - 1:0] x,
    input        [w_y     - 1:0] y,

    output logic [w_red   - 1:0] red,
    output logic [w_green - 1:0] green,
    output logic [w_blue  - 1:0] blue,

    // Microphone, sound output and UART

    input        [         23:0] mic,
    output       [         15:0] sound,

    input                        uart_rx,
    output                       uart_tx,

    // General-purpose Input/Output

    inout        [w_gpio  - 1:0] gpio
);

    //------------------------------------------------------------------------
    // Unused interfaces
    //------------------------------------------------------------------------

    assign sound    = '0;
    assign uart_tx  = '1;
    assign led      = '0;

    //------------------------------------------------------------------------
    // Fixed point arithmetic - Q4.24
    //------------------------------------------------------------------------

    localparam int FRAC_BITS = 24;

    // One Mandelbrot point is computed per BLOCK_SIZE x BLOCK_SIZE pixel block.

    localparam int BLOCK_LOG2 = $clog2 (BLOCK_SIZE);
    localparam int N_BX = screen_width  / BLOCK_SIZE;   // block columns
    localparam int N_BY = screen_height / BLOCK_SIZE;   // block rows
    localparam int W_BX = w_x - BLOCK_LOG2;             // block column bits
    localparam int W_BY = w_y - BLOCK_LOG2;             // block row bits
    localparam int ADDR_W = $clog2 (N_BX * N_BY);       // framebuffer address bits

    // Initial view of the complex plane, matching the MATLAB reference:
    // x in [-2.5, 1.5] with square cells, so the height follows the screen
    // aspect ratio. The step is the same for both axes.

    localparam logic signed [27:0] INIT_LEFT = -28'sd41943040;          // -2.5
    localparam logic signed [27:0] INIT_STEP = 28'sh4000000 / N_BX;     // 4.0 / N_BX
    localparam logic signed [27:0] INIT_TOP  = (64'sd33554432 * N_BY) / N_BX;  // 2.0 * N_BY / N_BX

    // The iteration limit follows the zoom level: every zoom-in press
    // increments the zoom level and every zoom-out press decrements it, and
    // the limit is MAX_ITER = max (1, min (31, ZOOM_LVL)). The framebuffer
    // removes the real-time budget of the old line-buffer design, so a
    // higher limit only makes the image refresh proportionally slower.

    localparam logic [5:0] INIT_ITER = 6'd24;   // the initial zoom level

    // Zoom factors, as in the MATLAB reference: 0.7 and 1 / 0.7.

    localparam logic signed [27:0] K_ZOOM_IN  = 28'sd11744051;   // 0.7
    localparam logic signed [27:0] K_ZOOM_OUT = 28'sd23967451;   // 1 / 0.7

    // The step size is limited so that the whole view always fits
    // into the Q4.24 range [-4, 4].

    localparam logic signed [27:0] STEP_MAX = 28'sh7800000 / N_BX;   // 7.5 / N_BX
    localparam logic signed [27:0] STEP_MIN = 28'sd1;                // 2^-24
    localparam logic signed [27:0] FOUR     = 28'sh4000000;          // 4.0

    // Pan by one eighth of the screen per press (the MATLAB reference
    // pans by 10 percent, which is close enough).

    localparam int PAN_X = N_BX / 8;
    localparam int PAN_Y = N_BY / 8;

    function automatic signed [27:0] mul_q (input signed [27:0] a, input signed [27:0] b);
        // Q4.24 x Q4.24 -> Q4.24

        logic signed [55:0] p;

        p = a * b;

        // Round half up: the zoom factors are reciprocal, so a zoom in
        // followed by a zoom out returns exactly to the previous step size.

        mul_q = (p + (1 << (FRAC_BITS - 1))) >>> FRAC_BITS;
    endfunction

    function automatic signed [27:0] clamp_q
        (input signed [27:0] v, input signed [27:0] lo, input signed [27:0] hi);

        if (v < lo)
            return lo;

        if (v > hi)
            return hi;

        return v;
    endfunction

    //------------------------------------------------------------------------
    // Debounce the keys and detect the press edges
    //------------------------------------------------------------------------

    wire [w_key - 1:0] key_deb;

    genvar i_key;

    generate
        for (i_key = 0; i_key < w_key; i_key++)
        begin : gen_key_deb

            sync_and_debounce_one
            # (
                .depth (debounce_depth)
            )
            i_deb
            (
                .clk    ( clk          ),
                .reset  ( rst          ),
                .sw_in  ( key [i_key]  ),
                .sw_out ( key_deb [i_key] )
            );

        end
    endgenerate

    wire [w_key - 1:0] key_pulse;

    pulse_on_0_to_1
    # (
        .w ( w_key )
    )
    i_key_pulse
    (
        .clk   ( clk       ),
        .rst   ( rst       ),
        .level ( key_deb   ),
        .pulse ( key_pulse )
    );

    // The lab uses up to eight keys; boards with fewer keys get zeroes here.

    wire [7:0] key_press = 8' (key_pulse);

    //------------------------------------------------------------------------
    // View state and its update on the key presses
    //------------------------------------------------------------------------

    logic signed [27:0] view_left, view_top, step;

    wire signed [27:0] step_zoom_in  = mul_q (step, K_ZOOM_IN);
    wire signed [27:0] step_zoom_out = mul_q (step, K_ZOOM_OUT);

    logic signed [27:0] view_left_next, view_top_next, step_next;
    logic        [ 5:0] zoom_lvl, zoom_lvl_next;

    // The zoom update is split into two stages to meet the 50 MHz period.
    // On the press, the next step size is computed (the DSP multiply) and
    // the zoom level is updated. One cycle later the view corners follow,
    // using the registered old and new step sizes. The pans and the reset
    // only involve registered values and apply on the press itself.

    always_comb
    begin
        step_next     = step;
        zoom_lvl_next = zoom_lvl;

        if (key_press [0])       // S1 - zoom in
        begin
            step_next = step_zoom_in;

            if (zoom_lvl < 6'd31)
                zoom_lvl_next = zoom_lvl + 6'd1;
        end
        else if (key_press [1])  // S2 - zoom out
        begin
            step_next = step_zoom_out;

            if (zoom_lvl > 6'd1)
                zoom_lvl_next = zoom_lvl - 6'd1;
        end
        else if (key_press [6] || key_press [7])  // S7, S8 - reset the view
        begin
            step_next     = INIT_STEP;
            zoom_lvl_next = INIT_ITER [5:0];
        end

        step_next = clamp_q (step_next, STEP_MIN, STEP_MAX);
    end

    // The iteration limit follows the zoom level, saturated to 1..31:
    // MAX_ITER = max (1, min (31, ZOOM_LVL)).

    wire [5:0] max_iter = (zoom_lvl < 6'd1) ? 6'd1
                        : (zoom_lvl > 6'd31) ? 6'd31
                        : zoom_lvl;

    // The step size captured on a press and the press pulse delayed by one
    // cycle: the zoom corner update uses them instead of the combinational
    // multiplier output.

    logic signed [27:0] step_on_press;
    logic        [ 7:0] key_press_r;

    always_ff @ (posedge clk)
    begin
        if (rst)
        begin
            step_on_press <= '0;
            key_press_r   <= '0;
        end
        else
        begin
            step_on_press <= step;
            key_press_r   <= key_press;
        end
    end

    always_comb
    begin
        view_left_next = view_left;
        view_top_next  = view_top;

        if (key_press_r [0])       // S1 - zoom in, one cycle after the step
        begin
            view_left_next = view_left + (N_BX / 2) * (step_on_press - step);
            view_top_next  = view_top  - (N_BY / 2) * (step_on_press - step);
        end
        else if (key_press_r [1])  // S2 - zoom out
        begin
            view_left_next = view_left - (N_BX / 2) * (step - step_on_press);
            view_top_next  = view_top  + (N_BY / 2) * (step - step_on_press);
        end
        else if (key_press [2])  // S3 - pan left
        begin
            view_left_next = view_left - PAN_X * step;
        end
        else if (key_press [3])  // S4 - pan right
        begin
            view_left_next = view_left + PAN_X * step;
        end
        else if (key_press [4])  // S5 - pan up
        begin
            view_top_next = view_top + PAN_Y * step;
        end
        else if (key_press [5])  // S6 - pan down
        begin
            view_top_next = view_top - PAN_Y * step;
        end
        else if (key_press [6] || key_press [7])  // S7, S8 - reset the view
        begin
            view_left_next = INIT_LEFT;
            view_top_next  = INIT_TOP;
        end

        // Clamp so that the view always stays inside the Q4.24 range [-4, 4].
        // The bounds use the registered step, so this path stays short; they
        // are at most one cycle behind the step update, which never pushes
        // the view out of range in the meantime.

        view_left_next = clamp_q (view_left_next, - FOUR, FOUR - N_BX * step);
        view_top_next  = clamp_q (view_top_next, N_BY * step - FOUR, FOUR);
    end

    always_ff @ (posedge clk)
    begin
        if (rst)
        begin
            view_left <= INIT_LEFT;
            view_top  <= INIT_TOP;
            step      <= INIT_STEP;
            zoom_lvl  <= INIT_ITER [5:0];
        end
        else
        begin
            view_left <= view_left_next;
            view_top  <= view_top_next;
            step      <= step_next;
            zoom_lvl  <= zoom_lvl_next;
        end
    end

    //------------------------------------------------------------------------
    // The TM1638 module's seven-segment display shows the iteration limit
    //------------------------------------------------------------------------

    wire [7:0] seg_abcdefgh;
    wire [1:0] seg_digit;

    seven_segment_display
    # (
        .w_digit   ( 2       ),
        .clk_mhz   ( clk_mhz ),
        .update_hz ( 120     )
    )
    i_seven_seg
    (
        .clk      ( clk          ),
        .rst      ( rst          ),
        .number   ( { 4' (max_iter / 6'd10), 4' (max_iter % 6'd10) } ),
        .dots     ( 2'b00        ),
        .abcdefgh ( seg_abcdefgh ),
        .digit    ( seg_digit    )
    );

    assign abcdefgh = seg_abcdefgh;
    assign digit    = seg_digit;

    //------------------------------------------------------------------------
    // Framebuffer: the persistent image, updated by the engine as the
    // computation progresses and always displayed at the full frame rate
    //------------------------------------------------------------------------

    // The color of every block is kept in a two-plane BRAM framebuffer: four
    // bits in the main plane and one bit in the side plane, which stores a
    // 5-bit value at the minimum BRAM cost. The display reads it through one
    // port; the engine writes it through the other.

    logic [3:0] fb_lo [0:N_BX * N_BY - 1];
    logic       fb_hi [0:N_BX * N_BY - 1];

    wire [W_BX - 1:0] dbx = x [w_x - 1:BLOCK_LOG2];   // displayed block column
    wire [W_BY - 1:0] dby = y [w_y - 1:BLOCK_LOG2];   // displayed block row

    // The display address is registered together with the BRAM output, so
    // the read takes two cycles and the picture is shifted by two pixels.

    logic [ADDR_W - 1:0] fb_rd_addr;

    always_ff @ (posedge clk)
    begin
        if (rst)
            fb_rd_addr <= '0;
        else
            fb_rd_addr <= dby * N_BX + dbx;
    end

    logic [4:0] color_idx;

    always_ff @ (posedge clk)
    begin
        if (rst)
            color_idx <= '0;
        else
            color_idx <= { fb_hi [fb_rd_addr], fb_lo [fb_rd_addr] };
    end

    //------------------------------------------------------------------------
    // Escape-time engine: one point per block, scanning the whole image
    //------------------------------------------------------------------------
    //
    // A single sequential engine scans the blocks row by row and writes each
    // result into the framebuffer. The scan runs continuously at its own
    // pace: with BLOCK_SIZE = 1 and MAX_ITER = 24 the whole image takes
    //   N_BX * N_BY * (MAX_ITER + 2) = 614400 * 26 = 16 million cycles,
    // about 320 ms, so the picture refreshes at about 3 Hz while the display
    // keeps showing the previous content at 60 Hz. Every key press restarts
    // the scan from the top with the new view.

    typedef enum logic [1:0]
    {
        S_IDLE,
        S_ITERATE,
        S_STORE
    }
    state_t;

    state_t state;

    logic [W_BY - 1:0] scan_by;
    logic [W_BX - 1:0] scan_bx;

    logic signed [27:0] eng_cx, eng_cy;   // coordinates of the current point
    logic signed [27:0] zx, zy;           // current iteration value z = zx + i*zy
    logic        [ 5:0] iter;             // current iteration number
    logic        [ 4:0] color;            // escape time of the current point

    // A key press requests the scan to restart from the top with the new
    // view. The flag latches the pulse, so a press during the iterations of
    // a point is not lost.

    wire any_press = | key_press;

    logic scan_restart;

    always_ff @ (posedge clk)
    begin
        if (rst)
            scan_restart <= 1'b1;
        else if (any_press)
            scan_restart <= 1'b1;
        else if (state == S_IDLE)
            scan_restart <= 1'b0;
    end

    // Iteration arithmetic: z_next = z^2 + c

    logic signed [55:0] zx2_full, zy2_full, zxzy_full;

    assign zx2_full  = $signed (zx) * $signed (zx);
    assign zy2_full  = $signed (zy) * $signed (zy);
    assign zxzy_full = $signed (zx) * $signed (zy);

    // The squares are kept in 32 bits: the engine iterates points with
    // |z| <= 2, so z^2 can reach 64.0, which does not fit the 28-bit Q4.24
    // values themselves. The z registers truncate to Q4.24; the possible
    // wrap of |z| at 8.0 cannot hide the escape, because the magnitude of
    // the square is preserved by the wrap.

    wire signed [31:0] zx2  = zx2_full  [55:24];
    wire signed [31:0] zy2  = zy2_full  [55:24];
    wire signed [31:0] zxzy = zxzy_full [55:24];

    // The point escapes when |z|^2 > 4. The comparison uses the truncated
    // squares: the truncation is exact within one LSB of the threshold and
    // only shifts the color of the boundary points by one iteration.

    wire signed [31:0] sq     = zx2 + zy2;
    wire               escaped = sq > FOUR;

    wire signed [27:0] zx_next = zx2 - zy2 + eng_cx;
    wire signed [27:0] zy_next = (zxzy <<< 1) + eng_cy;

    always_ff @ (posedge clk)
    begin
        if (rst)
        begin
            state    <= S_IDLE;
            scan_by  <= '0;
            scan_bx  <= '0;
            eng_cx   <= '0;
            eng_cy   <= '0;
            zx       <= '0;
            zy       <= '0;
            iter     <= '0;
            color    <= '0;
        end
        else
        begin
            case (state)

            S_IDLE:
            begin
                // (Re)start the scan from the top with the current view.

                scan_by <= '0;
                scan_bx <= '0;
                eng_cx  <= view_left;
                eng_cy  <= view_top;
                zx      <= '0;
                zy      <= '0;
                iter    <= '0;
                state   <= S_ITERATE;
            end

            S_ITERATE:
            begin
                if (scan_restart)
                    state <= S_IDLE;
                else if (iter == max_iter)
                begin
                    // The point never escaped: it belongs to the set. The
                    // sentinel for the interior is 0, a fixed value that
                    // stays valid while the iteration limit changes with
                    // the zoom level.

                    color <= '0;
                    state <= S_STORE;
                end
                else if (escaped)
                begin
                    // The escape time is the current iteration number.

                    color <= iter [4:0];
                    state <= S_STORE;
                end
                else
                begin
                    zx   <= zx_next;
                    zy   <= zy_next;
                    iter <= iter + 6'd1;
                end
            end

            S_STORE:
            begin
                // Write the color of this point into the framebuffer and
                // advance the scan to the next point.

                fb_lo [scan_by * N_BX + scan_bx] <= color [3:0];
                fb_hi [scan_by * N_BX + scan_bx] <= color [4];

                if (scan_bx == N_BX - 1)
                begin
                    scan_bx <= '0;
                    eng_cx  <= view_left;

                    if (scan_by == N_BY - 1)
                    begin
                        scan_by <= '0;
                        eng_cy  <= view_top;
                    end
                    else
                    begin
                        scan_by <= scan_by + 1'b1;
                        eng_cy  <= eng_cy - step;
                    end
                end
                else
                begin
                    scan_bx <= scan_bx + 1'b1;
                    eng_cx  <= eng_cx + step;
                end

                if (scan_restart)
                    state <= S_IDLE;
                else
                begin
                    zx    <= '0;
                    zy    <= '0;
                    iter  <= '0;
                    state <= S_ITERATE;
                end
            end

            endcase
        end
    end

    //------------------------------------------------------------------------
    // Palette and the RGB output
    //------------------------------------------------------------------------

    function automatic [23:0] palette (input [4:0] idx);
        case (idx)
            5'd1 : palette = 24'h000080;
            5'd2 : palette = 24'h0000FF;
            5'd3 : palette = 24'h0040FF;
            5'd4 : palette = 24'h0080FF;
            5'd5 : palette = 24'h00C0FF;
            5'd6 : palette = 24'h00FFFF;
            5'd7 : palette = 24'h00FFC0;
            5'd8 : palette = 24'h00FF80;
            5'd9 : palette = 24'h00FF40;
            5'd10: palette = 24'h00FF00;
            5'd11: palette = 24'h40FF00;
            5'd12: palette = 24'h80FF00;
            5'd13: palette = 24'hC0FF00;
            5'd14: palette = 24'hFFFF00;
            5'd15: palette = 24'hFFC000;
            5'd16: palette = 24'hFF8000;
            5'd17: palette = 24'hFF4000;
            5'd18: palette = 24'hFF0000;
            5'd19: palette = 24'hFF0040;
            5'd20: palette = 24'hFF0080;
            5'd21: palette = 24'hFF00C0;
            5'd22: palette = 24'hFF00FF;
            5'd23: palette = 24'hC000FF;
            5'd24: palette = 24'h8000FF;
            5'd25: palette = 24'h4000FF;
            5'd26: palette = 24'h3000C0;
            5'd27: palette = 24'h200080;
            5'd28: palette = 24'h100040;
            5'd29: palette = 24'h080030;
            5'd30: palette = 24'h040020;
            5'd31: palette = 24'h000010;
            default: palette = 24'h000000;
        endcase
    endfunction

    // The interior of the set (the sentinel 0) is black; the escape time
    // selects the color.

    wire [23:0] rgb = (color_idx == 5'd0) ? 24'h000000 : palette (color_idx);

    assign red   = rgb [23 -: w_red];
    assign green = rgb [15 -: w_green];
    assign blue  = rgb [ 7 -: w_blue];

endmodule
