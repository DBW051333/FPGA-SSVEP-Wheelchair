// Byte broadcast consumer; no UART transmitter and no influence on SSVEP actions.
module eeg_metrics #(parameter CLOCK_HZ=27000000)(
 input wire clk,rst_n,running,byte_valid,byte_error,input wire [7:0] byte_data,
 output wire [6:0] score,output wire valid,stream_on,signal_fresh,fault,
 output wire [1:0] emotion_label,output wire [2:0] emotion_state);
 localparam integer FRESH_WIDTH=$clog2(CLOCK_HZ+1);
 reg [FRESH_WIDTH-1:0] fresh_count;
 wire sample_valid,ready,overrun;wire signed [31:0] s0,s1,s2,s3;wire [15:0] seq;
 always @(posedge clk)begin
  if(!rst_n||!running)fresh_count<=0;
  else if(sample_valid)fresh_count<=0;
  else if(fresh_count<CLOCK_HZ)fresh_count<=fresh_count+1'b1;
 end
 attention_cyton_rx #(.CLOCK_HZ(CLOCK_HZ)) parser(.clk(clk),.rst_n(rst_n&&running),
  .byte_valid(byte_valid),.byte_error(byte_error),.byte_data(byte_data),.sample_valid(sample_valid),
  .sample_ready(ready),.sample0(s0),.sample1(s1),.sample2(s2),.sample3(s3),.sample_sequence(seq),
  .overrun(overrun),.malformed_packets(),.gap_over_5ms(),.gap_over_50ms(),.timeout_errors(),.footer_errors());

 wire emotion_sample,emotion_gap,emotion_busy,emotion_result,emotion_overrun;
 wire [255:0] emotion_samples;
 wire signed [15:0] emotion_score0,emotion_score1,emotion_score2;
 emotion_rx8 #(.CLOCK_HZ(CLOCK_HZ)) emotion_parser(
  .clk(clk),.rst_n(rst_n&&running),.byte_valid(byte_valid),.byte_error(byte_error),.byte_data(byte_data),
  .sample_valid(emotion_sample),.samples(emotion_samples),.discontinuity(emotion_gap),.sequence_number());
 emotion_core emotion_engine(.clk(clk),.rst_n(rst_n&&running&&signal_fresh),.enable(running),
  .sample_valid(emotion_sample),.discontinuity(emotion_gap),.samples(emotion_samples),
  .busy(emotion_busy),.result_valid(emotion_result),.label(emotion_label),
  .score0(emotion_score0),.score1(emotion_score1),.score2(emotion_score2),.overrun(emotion_overrun));
 reg emotion_have_result;reg [31:0] emotion_age;
 always @(posedge clk)begin
  if(!rst_n||!running||!signal_fresh||emotion_gap||emotion_overrun)begin
   emotion_have_result<=0;emotion_age<=CLOCK_HZ*3;
  end else begin
   if(emotion_age<CLOCK_HZ*3)emotion_age<=emotion_age+1'b1;
   if(emotion_result)begin emotion_have_result<=1;emotion_age<=0;end
  end
 end
 // 0 waiting,1 collecting,2 computing,3 result,4 stale.
 assign emotion_state=!running?0:!signal_fresh?4:
  (emotion_have_result&&emotion_age<CLOCK_HZ*3)?3:emotion_busy?2:1;
 wire core_fault,core_valid;wire [2:0] channels;
 // Match the original monitor: retain received samples across packet-ID gaps.
 // Only a stopped/stale session clears the accumulated four-second buffer.
 attention_core core(.clk(clk),.rst_n(rst_n&&running&&signal_fresh),
  .sample_valid(sample_valid),.sample0(s0),.sample1(s1),.sample2(s2),.sample3(s3),
  .ready(ready),.score(score),.valid(core_valid),.updated(),.good_channels(channels),.fault(core_fault));
 assign stream_on=running;
 assign signal_fresh=running&&fresh_count<CLOCK_HZ*3/4;
 assign valid=core_valid&&signal_fresh&&!core_fault&&!overrun;
 assign fault=core_fault||overrun||emotion_overrun;
endmodule
