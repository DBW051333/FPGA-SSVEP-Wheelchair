`timescale 1ns/1ps
// TLV5618A: BUFFER Y first, then update X and Y together.
module dac_pair_driver #(
    parameter integer SCLK_HALF_CYCLES=25
)(
    input wire clk,
    input wire [11:0] target_x,target_y,
    output reg dac_din,
    output reg dac_sclk,
    output reg dac_cs_n
);
    initial begin dac_din=0;dac_sclk=1;dac_cs_n=1;end
    localparam [11:0] CODE_1V6=12'h666;
    localparam integer DIV_WIDTH=(SCLK_HALF_CYCLES>1)?$clog2(SCLK_HALF_CYCLES):1;
    reg first_pair=1;
    // All logic uses clk. SCLK is an output register, not an internal clock.
    localparam START = 3'd0, FALL = 3'd1, RISE = 3'd2,
               FINISH = 3'd3, GAP = 3'd4;
    reg [2:0] state = START;
    reg [DIV_WIDTH-1:0] divider = 0;
    reg phase_a = 0;
    reg [15:0] shift_word = 0;
    reg [3:0] bit_index = 15;
    reg [11:0] saved_a = CODE_1V6;
    always @(posedge clk) begin
        if (divider == SCLK_HALF_CYCLES-1) begin
            divider <= 0;
            case (state)
                START: begin
                    // Freeze a pair at the beginning of the BUFFER frame.
                    // Slow, normal mode: 0x1xxx BUFFER, then 0x8xxx A + B.
                    if (!phase_a) begin
                        saved_a <= first_pair ? CODE_1V6 : target_x;
                        shift_word <= {4'h1, first_pair ? CODE_1V6 : target_y};
                        dac_din <= 1'b0;
                    end else begin
                        shift_word <= {4'h8, saved_a};
                        dac_din <= 1'b1;
                    end
                    dac_cs_n <= 1'b0;
                    bit_index <= 15;
                    state <= FALL;
                end
                FALL: begin
                    dac_sclk <= 1'b0; // DAC samples the current bit here.
                    state <= RISE;
                end
                RISE: begin
                    dac_sclk <= 1'b1;
                    if (bit_index == 0) begin
                        // This rising edge commits the complete DAC command.
                        state <= FINISH;
                    end else begin
                        shift_word <= {shift_word[14:0], 1'b0};
                        dac_din <= shift_word[14];
                        bit_index <= bit_index - 1'b1;
                        state <= FALL;
                    end
                end
                FINISH: begin
                    dac_cs_n <= 1'b1;
                    state <= GAP;
                end
                GAP: begin
                    phase_a <= !phase_a;
                    if(phase_a) first_pair <= 0;
                    state <= START;
                end
                default: begin
                    dac_cs_n <= 1'b1;
                    dac_sclk <= 1'b1;
                    phase_a <= 1'b0;
                    state <= START;
                end
            endcase
        end else begin
            divider <= divider + 1'b1;
        end
    end
endmodule
