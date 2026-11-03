`timescale 1ns/1ps
module panel_reader(
    input wire clk, rst_n,
    input wire mute_led, sos_led, d5, d6, ser, rclk, srclk,
    output wire [11:0] led_on,
    output wire direct_valid,
    output reg serial_valid
);
    // Inputs are already conditioned digital levels. No pull-up on panel nodes.
    (* syn_preserve=1, ASYNC_REG="TRUE" *) reg [6:0] sync_meta, sync_data;
    reg old_srclk, old_rclk;
    reg [1:0] prime_count;
    reg [7:0] shift_reg, latch_reg;
    reg [3:0] seen_bits;
    assign direct_valid = (prime_count == 3);
    // Panel LEDs are active HIGH. Display segment polarity is independent.
    // [11]=SOS, [10]=mute, [9:5]=D9..D5, [4:0]=D4..D0.
    assign led_on = {sync_data[1:0], latch_reg[7:5],
                     sync_data[3:2], latch_reg[4:0]};
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            sync_meta <= 7'b0000000; sync_data <= 7'b0000000;
            old_srclk <= 0; old_rclk <= 0; prime_count <= 0;
            shift_reg <= 8'h00; latch_reg <= 8'h00;
            seen_bits <= 0; serial_valid <= 0;
        end else begin
            sync_meta <= {srclk,rclk,ser,d6,d5,sos_led,mute_led};
            sync_data <= sync_meta;
            old_srclk <= sync_data[6]; old_rclk <= sync_data[5];
            if(prime_count != 3) prime_count <= prime_count + 1'b1;
            if(direct_valid && sync_data[6] && !old_srclk) begin
                shift_reg <= {shift_reg[6:0],sync_data[4]};
                if(seen_bits < 8) seen_bits <= seen_bits + 1'b1;
            end
            if(direct_valid && sync_data[5] && !old_rclk) begin
                // Nonblocking assignments latch the pre-shift value on equal edges.
                latch_reg <= shift_reg;
                serial_valid <= (seen_bits == 8);
            end
        end
    end
endmodule
