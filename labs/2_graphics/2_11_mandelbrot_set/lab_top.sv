`include "config.svh"

// Interactive Mandelbrot set.
//
// The complex plane is shown on the screen. The image is computed in real time
// by a sequential escape-time engine: one point per 4x4 pixel block. The colors
// of the row the display is about to enter are computed in advance and kept in
// a double-buffered line buffer, so the picture has no per-block artifacts.
//
// Controls (keys come from the TM1638 module buttons, S8 -> key[0] ... S1 -> key[7]):
//   key[0] (S8) - zoom in      (MATLAB reference: Q)
//   key[1] (S7) - zoom out     (MATLAB reference: E)
//   key[2] (S6) - pan right    (MATLAB reference: D)
//   key[3] (S5) - pan left     (MATLAB reference: A)
//   key[4] (S4) - pan up       (MATLAB reference: W)
//   key[5] (S3) - pan down     (MATLAB reference: S)
//   key[6] (S2) - reset the view
//   key[7] (S1) - reset the view (spare)
//
// The current iteration limit is shown on the TM1638 module LEDs.

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
               w_y           = $clog2 ( screen_height )
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
    assign abcdefgh = '0;
    assign digit    = '0;

    //------------------------------------------------------------------------
    // Fixed point arithmetic - Q4.28
    //------------------------------------------------------------------------

    localparam int FRAC_BITS = 28;

    // One Mandelbrot point is computed per BLOCK_SIZE x BLOCK_SIZE pixel block.

    localparam int BLOCK_SIZE = 4;
    localparam int N_BX = screen_width  / BLOCK_SIZE;   // block columns
    localparam int N_BY = screen_height / BLOCK_SIZE;   // block rows

    // Initial view of the complex plane, matching the MATLAB reference:
    // x in [-2.5, 1.5], y in [-1.5, 1.5], maxIter = 20.

    localparam logic signed [31:0] INIT_LEFT = -32'sd671088640;  // -2.5
    localparam logic signed [31:0] INIT_TOP  =  32'sd402653184;  // +1.5

    // The initial step is the whole view divided by the number of blocks.

    localparam logic signed [31:0] INIT_X_STEP = 32'sh40000000 / N_BX;  // 4.0 / N_BX
    localparam logic signed [31:0] INIT_Y_STEP = 32'sh30000000 / N_BY;  // 3.0 / N_BY

    localparam int INIT_ITER    = 20;
    localparam int ITER_MAX_CAP = 26;
    localparam int ITER_MIN_CAP = 12;

    // Zoom factors, as in the MATLAB reference: 0.7 and 1 / 0.7.

    localparam logic signed [31:0] K_ZOOM_IN  = 32'sd187904819;  // 0.7
    localparam logic signed [31:0] K_ZOOM_OUT = 32'sd383479223;  // 1 / 0.7

    // The step size is limited so that the whole view always fits
    // into the Q4.28 range [-4, 4].

    localparam logic signed [31:0] STEP_MAX = 32'sd10737418;  // 0.04
    localparam logic signed [31:0] STEP_MIN = 32'sd16;        // 2^-24
    localparam logic signed [31:0] FOUR     = 32'sh40000000;  // 4.0

    // Pan by one eighth of the screen per press (the MATLAB reference
    // pans by 10 percent, which is close enough).

    localparam int PAN_X = N_BX / 8;
    localparam int PAN_Y = N_BY / 8;

    function automatic signed [31:0] mul_q (input signed [31:0] a, input signed [31:0] b);
        // Q4.28 x Q4.28 -> Q4.28

        logic signed [63:0] p;

        p = a * b;

        mul_q = p >>> FRAC_BITS;
    endfunction

    function automatic signed [31:0] clamp_q
        (input signed [31:0] v, input signed [31:0] lo, input signed [31:0] hi);

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
                .depth (19)   // 2^19 clock cycles ~ 10 ms at 50 MHz
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

    logic signed [31:0] view_left, view_top, x_step, y_step;
    logic        [ 5:0] max_iter;

    wire signed [31:0] x_step_zoom_in  = mul_q (x_step, K_ZOOM_IN);
    wire signed [31:0] x_step_zoom_out = mul_q (x_step, K_ZOOM_OUT);
    wire signed [31:0] y_step_zoom_in  = mul_q (y_step, K_ZOOM_IN);
    wire signed [31:0] y_step_zoom_out = mul_q (y_step, K_ZOOM_OUT);

    logic signed [31:0] view_left_next, view_top_next, x_step_next, y_step_next;
    logic        [ 5:0] max_iter_next;

    always_comb
    begin
        view_left_next = view_left;
        view_top_next  = view_top;
        x_step_next    = x_step;
        y_step_next    = y_step;
        max_iter_next  = max_iter;

        if (key_press [0])       // S8 - zoom in
        begin
            x_step_next    = x_step_zoom_in;
            y_step_next    = y_step_zoom_in;
            view_left_next = view_left + (N_BX / 2) * (x_step - x_step_zoom_in);
            view_top_next  = view_top  - (N_BY / 2) * (y_step - y_step_zoom_in);

            if (max_iter < ITER_MAX_CAP)
                max_iter_next = max_iter + 6'd1;
        end
        else if (key_press [1])  // S7 - zoom out
        begin
            x_step_next    = x_step_zoom_out;
            y_step_next    = y_step_zoom_out;
            view_left_next = view_left - (N_BX / 2) * (x_step_zoom_out - x_step);
            view_top_next  = view_top  + (N_BY / 2) * (y_step_zoom_out - y_step);

            if (max_iter > ITER_MIN_CAP)
                max_iter_next = max_iter - 6'd1;
        end
        else if (key_press [2])  // S6 - pan right
        begin
            view_left_next = view_left + PAN_X * x_step;
        end
        else if (key_press [3])  // S5 - pan left
        begin
            view_left_next = view_left - PAN_X * x_step;
        end
        else if (key_press [4])  // S4 - pan up
        begin
            view_top_next = view_top + PAN_Y * y_step;
        end
        else if (key_press [5])  // S3 - pan down
        begin
            view_top_next = view_top - PAN_Y * y_step;
        end
        else if (key_press [6] || key_press [7])  // S2, S1 - reset the view
        begin
            view_left_next = INIT_LEFT;
            view_top_next  = INIT_TOP;
            x_step_next    = INIT_X_STEP;
            y_step_next    = INIT_Y_STEP;
            max_iter_next  = INIT_ITER [5:0];
        end

        // Clamp so that the view always stays inside the Q4.28 range [-4, 4].

        x_step_next    = clamp_q (x_step_next, STEP_MIN, STEP_MAX);
        y_step_next    = clamp_q (y_step_next, STEP_MIN, STEP_MAX);
        view_left_next = clamp_q (view_left_next, - FOUR, FOUR - N_BX * x_step_next);
        view_top_next  = clamp_q (view_top_next, N_BY * y_step_next - FOUR, FOUR);
    end

    always_ff @ (posedge clk)
    begin
        if (rst)
        begin
            view_left <= INIT_LEFT;
            view_top  <= INIT_TOP;
            x_step    <= INIT_X_STEP;
            y_step    <= INIT_Y_STEP;
            max_iter  <= INIT_ITER [5:0];
        end
        else
        begin
            view_left <= view_left_next;
            view_top  <= view_top_next;
            x_step    <= x_step_next;
            y_step    <= y_step_next;
            max_iter  <= max_iter_next;
        end
    end

    // The TM1638 module LEDs show the current iteration limit.

    assign led = w_led' (max_iter);

    //------------------------------------------------------------------------
    // Escape-time engine: one point per BLOCK_SIZE x BLOCK_SIZE pixel block
    //------------------------------------------------------------------------

    wire [w_x - 3:0] bx = x [w_x - 1:2];   // block column, 0 .. N_BX - 1
    wire [w_y - 3:0] by = y [w_y - 1:2];   // block row,    0 .. N_BY - 1

    // The row the engine is computing: the one the display enters next.

    wire [w_y - 3:0] next_row = (by == N_BY - 1) ? '0 : by + 1'b1;

    typedef enum logic [1:0]
    {
        S_IDLE,
        S_ITERATE,
        S_STORE
    }
    state_t;

    state_t state;

    logic [6:0] by_r;
    logic       disp_sel;

    wire row_change = (by != by_r);

    // One line buffer per row, double buffered: the display reads one while
    // the engine fills the other.

    logic [4:0] line_buf [2][N_BX];

    logic signed [31:0] eng_cx, eng_cy;   // coordinates of the current point
    logic signed [31:0] zx, zy;           // current iteration value z = zx + i*zy
    logic        [ 5:0] iter;             // current iteration number
    logic        [ 4:0] color;            // escape time of the current point
    logic        [ 7:0] bx_idx;           // block column being computed

    // Iteration arithmetic: z_next = z^2 + c

    logic signed [63:0] zx2_full, zy2_full, zxzy_full;

    assign zx2_full  = $signed (zx) * $signed (zx);
    assign zy2_full  = $signed (zy) * $signed (zy);
    assign zxzy_full = $signed (zx) * $signed (zy);

    wire signed [31:0] zx2  = zx2_full  [59:28];
    wire signed [31:0] zy2  = zy2_full  [59:28];
    wire signed [31:0] zxzy = zxzy_full [59:28];

    // The point escapes when |z|^2 > 4, i.e. the raw sum of squares
    // exceeds 4 * 2^(2*FRAC_BITS).

    wire [63:0] sq     = zx2_full + zy2_full;
    wire       escaped = sq > (64'h4 << (2 * FRAC_BITS));

    wire signed [31:0] zx_next = zx2 - zy2 + eng_cx;
    wire signed [31:0] zy_next = (zxzy <<< 1) + eng_cy;

    wire signed [31:0] row_offset;
    assign row_offset = $signed ({1'b0, next_row}) * y_step;

    always_ff @ (posedge clk)
    begin
        if (rst)
        begin
            state    <= S_IDLE;
            by_r     <= '0;
            disp_sel <= 1'b0;
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
            by_r <= by;

            case (state)

            S_IDLE:
            begin
                if (row_change)
                begin
                    disp_sel <= ~ disp_sel;
                    eng_cx   <= view_left;
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
                if (iter == max_iter)
                begin
                    // The point never escaped: it belongs to the set.

                    color <= max_iter [4:0];
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
                // Store the color of this point into the line buffer that is
                // not being displayed, and start the next point of the row.

                line_buf [~ disp_sel] [bx_idx] <= color;

                if (bx_idx == N_BX - 1)
                    state <= S_IDLE;
                else
                begin
                    eng_cx <= eng_cx + x_step;
                    bx_idx <= bx_idx + 8'd1;
                    zx     <= '0;
                    zy     <= '0;
                    iter   <= '0;
                    state  <= S_ITERATE;
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

    wire [4:0] color_idx = line_buf [disp_sel] [bx];

    // The interior of the set is black; the escape time selects the color.

    wire [23:0] rgb = (color_idx == max_iter [4:0]) ? 24'h000000 : palette (color_idx);

    assign red   = rgb [23 -: w_red];
    assign green = rgb [15 -: w_green];
    assign blue  = rgb [ 7 -: w_blue];

endmodule
