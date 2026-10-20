`include "config.svh"

// Interactive Mandelbrot set.
//
// The complex plane is shown on the screen. The image is computed in real time
// by a sequential escape-time engine: one point per 4x4 pixel block. The colors
// of the row the display is about to enter are computed in advance and kept in
// a double-buffered line buffer, so the picture has no per-block artifacts.
//
// The board runs the lab on the 50 MHz pixel clock of the 1024x600 video
// mode: the lab and the display share one clock domain, so every path from
// the pixel coordinates to the RGB output has a full 20 ns pixel period.
// (An 1.25:1 clock ratio was tried and failed in hardware: the phase beats
// of the 62.5/50 MHz pair leave only 4 ns for the combinational display
// path, so the screen showed garbage.) The display read is pipelined with
// one register: the large line buffer mux fits into one pixel period, and
// the picture is simply shifted by one pixel.
//
// The view keeps square cells of the complex plane, so the picture is not
// distorted on any screen: the initial view spans [-2.5, 1.5] horizontally,
// and its height follows the screen aspect ratio.
//
// The coordinates are fixed point Q4.24 (28 bits). The 28x28 multipliers fit
// into two cascaded DSPs instead of four, and the zoom update is split into
// two stages, so every combinational path meets the 62.5 MHz lab period with
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
// The iteration limit is fixed at 31, as in the MATLAB reference where the
// maxIter updates are commented out: zooming changes only the view, never
// the rendering accuracy. 31 is the largest value that fits the 5-bit color
// field (it is also the sentinel for the interior of the set), and it is
// affordable at the maximum per-pixel (1x1) resolution thanks to 32
// escape-time engines computing the pixel columns in parallel. The limit is
// shown on the TM1638 module's seven-segment display (the two rightmost
// digits).

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

               debounce_depth = 19
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

    // One Mandelbrot point is computed per pixel: BLOCK_SIZE = 1 gives the
    // maximum resolution. The engines work per display line with a
    // double-buffered line buffer.

    localparam int BLOCK_SIZE = 1;
    localparam int BLOCK_LOG2 = $clog2 (BLOCK_SIZE);    // log2 of the block size
    localparam int N_BX = screen_width  / BLOCK_SIZE;   // block columns
    localparam int N_BY = screen_height / BLOCK_SIZE;   // block rows

    // Initial view of the complex plane, matching the MATLAB reference:
    // x in [-2.5, 1.5] with square cells, so the height follows the screen
    // aspect ratio. The step is the same for both axes.

    localparam logic signed [27:0] INIT_LEFT = -28'sd41943040;          // -2.5
    localparam logic signed [27:0] INIT_STEP = 28'sh4000000 / N_BX;     // 4.0 / N_BX
    localparam logic signed [27:0] INIT_TOP  = (64'sd33554432 * N_BY) / N_BX;  // 2.0 * N_BY / N_BX

    // The iteration limit is fixed: zooming changes only the view, not the
    // rendering accuracy. The value uses the full 5-bit color range: 31 is
    // the sentinel for the interior of the set, 1..30 are escape times.

    localparam logic [5:0] MAX_ITER = 6'd31;

    // Each escape-time engine owns a contiguous segment of SEG_SIZE columns.
    // With the lab running at the 50 MHz pixel clock, one display line lasts
    // 1344 lab cycles, and a point costs at most (MAX_ITER + 2) = 33 cycles:
    //   SEG_SIZE * 33 = 32 * 33 = 1056 cycles per line (79 % of the budget).
    // Every segment has a single writer, so the synthesizer maps the line
    // buffers to small memories instead of duplicating a shared buffer per
    // write port (which blew the design up to 286720 registers). 32 engines
    // x 3 DSP multipliers = 96 DSPs, well within the device.

    localparam int SEG_SIZE = 32;
    localparam int SEG_LOG2 = $clog2 (SEG_SIZE);
    localparam int N_ENG = (N_BX + SEG_SIZE - 1) / SEG_SIZE;

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

    // The zoom update is split into two stages to meet the 62.5 MHz lab
    // period. On the press, the next step size is computed (the DSP
    // multiply). One cycle later the view corners follow, using the
    // registered old and new step sizes. The pans and the reset only involve
    // registered values and apply on the press itself.

    always_comb
    begin
        step_next = step;

        if (key_press [0])       // S1 - zoom in
            step_next = step_zoom_in;
        else if (key_press [1])  // S2 - zoom out
            step_next = step_zoom_out;
        else if (key_press [6] || key_press [7])  // S7, S8 - reset the view
            step_next = INIT_STEP;

        step_next = clamp_q (step_next, STEP_MIN, STEP_MAX);
    end

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
        end
        else
        begin
            view_left <= view_left_next;
            view_top  <= view_top_next;
            step      <= step_next;
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
        .number   ( { 4' (MAX_ITER / 6'd10), 4' (MAX_ITER % 6'd10) } ),
        .dots     ( 2'b00        ),
        .abcdefgh ( seg_abcdefgh ),
        .digit    ( seg_digit    )
    );

    assign abcdefgh = seg_abcdefgh;
    assign digit    = seg_digit;

    //------------------------------------------------------------------------
    // Escape-time engine: one point per BLOCK_SIZE x BLOCK_SIZE pixel block
    //------------------------------------------------------------------------

    wire [w_x - BLOCK_LOG2 - 1:0] bx = x [w_x - 1:BLOCK_LOG2];   // column, 0 .. N_BX - 1
    wire [w_y - BLOCK_LOG2 - 1:0] by = y [w_y - 1:BLOCK_LOG2];   // row,    0 .. N_BY - 1

    // The line the engines are computing: the one the display enters next.

    wire [w_y - BLOCK_LOG2 - 1:0] next_row = (by == N_BY - 1) ? '0 : by + 1'b1;

    typedef enum logic [1:0]
    {
        S_IDLE,
        S_ITERATE,
        S_STORE
    }
    state_t;

    // Shared row tracking: the row change pulse starts all the engines, and
    // engine 0 also toggles the buffer select for the whole row.

    logic [w_y - BLOCK_LOG2 - 1:0] by_r;
    logic       disp_sel;

    always_ff @ (posedge clk)
    begin
        if (rst)
        begin
            by_r     <= '0;
            disp_sel <= 1'b0;
        end
        else
            by_r <= by;
    end

    wire row_change = (by != by_r);

    // One line buffer per row, double buffered: the display reads one while
    // the engines fill the other. Each engine writes only its own segment,
    // so every memory has a single write port.

    logic [4:0] line_buf [2][N_ENG][SEG_SIZE];

    wire signed [27:0] row_offset;
    assign row_offset = $signed ({1'b0, next_row}) * step;

    // N_ENG escape-time engines compute the points of one line together:
    // engine e owns the contiguous columns e * SEG_SIZE .. e * SEG_SIZE + 31
    // and walks them left to right. The worst case of a point (all the
    // iterations without an escape) takes MAX_ITER + 2 = 33 cycles:
    //   SEG_SIZE * 33 = 1056 cycles per line, 79 % of the 1344 cycles
    // available at the 50 MHz pixel clock.

    for (genvar e = 0; e < N_ENG; e++)
    begin : gen_eng

        logic signed [27:0] eng_cx, eng_cy;   // coordinates of the current point
        logic signed [27:0] zx, zy;           // current iteration value z = zx + i*zy
        logic        [ 5:0] iter;             // current iteration number
        logic        [ 4:0] color;            // escape time of the current point
        logic [SEG_LOG2 - 1:0] bx_idx;        // column within this segment

        // Iteration arithmetic: z_next = z^2 + c

        logic signed [55:0] zx2_full, zy2_full, zxzy_full;

        assign zx2_full  = $signed (zx) * $signed (zx);
        assign zy2_full  = $signed (zy) * $signed (zy);
        assign zxzy_full = $signed (zx) * $signed (zy);

        // The squares are kept in 32 bits: the engines iterate points with
        // |z| <= 2, so z^2 can reach 64.0, which does not fit the 28-bit
        // Q4.24 values themselves. The z registers truncate to Q4.24; the
        // possible wrap of |z| at 8.0 cannot hide the escape, because the
        // magnitude of the square is preserved by the wrap.

        wire signed [31:0] zx2  = zx2_full  [55:24];
        wire signed [31:0] zy2  = zy2_full  [55:24];
        wire signed [31:0] zxzy = zxzy_full [55:24];

        // The point escapes when |z|^2 > 4. The comparison uses the truncated
        // squares: the truncation is exact within one LSB of the threshold
        // and only shifts the color of the boundary points by one iteration.

        wire signed [31:0] sq     = zx2 + zy2;
        wire               escaped = sq > FOUR;

        wire signed [27:0] zx_next = zx2 - zy2 + eng_cx;
        wire signed [27:0] zy_next = (zxzy <<< 1) + eng_cy;

        state_t state;

        always_ff @ (posedge clk)
        begin
            if (rst)
            begin
                state    <= S_IDLE;
                eng_cx   <= '0;
                eng_cy   <= '0;
                zx       <= '0;
                zy       <= '0;
                iter     <= '0;
                color    <= '0;
                bx_idx   <= '0;
            end
            else
            begin
                case (state)

                S_IDLE:
                begin
                    if (row_change)
                    begin
                        // Engine 0 owns the buffer swap for the whole row.

                        if (e == 0)
                            disp_sel <= ~ disp_sel;

                        eng_cx   <= view_left + e * SEG_SIZE * step;
                        eng_cy   <= view_top - row_offset;
                        bx_idx   <= '0;
                        zx       <= '0;
                        zy       <= '0;
                        iter     <= '0;
                        state    <= S_ITERATE;
                    end
                end

                S_ITERATE:
                begin
                    if (iter == MAX_ITER)
                    begin
                        // The point never escaped: it belongs to the set.

                        color <= MAX_ITER [4:0];
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
                    // Store the color of this point into the segment of the
                    // line buffer that is not being displayed, and start the
                    // next point of the segment.

                    line_buf [~ disp_sel] [e] [bx_idx] <= color;

                    if (bx_idx == SEG_SIZE - 1)
                        state <= S_IDLE;
                    else
                    begin
                        eng_cx <= eng_cx + step;
                        bx_idx <= bx_idx + 1'b1;
                        zx     <= '0;
                        zy     <= '0;
                        iter   <= '0;
                        state  <= S_ITERATE;
                    end
                end

                endcase
            end
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

    // Pipelined display read: the big line buffer mux is registered once,
    // so its delay fits into one pixel period. The picture is simply shifted
    // by one pixel.

    logic [4:0] color_idx;

    always_ff @ (posedge clk)
    begin
        if (rst)
            color_idx <= '0;
        else
            color_idx <= line_buf [disp_sel] [bx [w_x - BLOCK_LOG2 - 1:SEG_LOG2]]
                                              [bx [SEG_LOG2 - 1:0]];
    end

    // The interior of the set is black; the escape time selects the color.

    wire [23:0] rgb = (color_idx == MAX_ITER [4:0]) ? 24'h000000 : palette (color_idx);

    assign red   = rgb [23 -: w_red];
    assign green = rgb [15 -: w_green];
    assign blue  = rgb [ 7 -: w_blue];

endmodule
