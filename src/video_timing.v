// 1280x720 @ 60 Hz: 74.25 MHz, positive HS/VS, 1650x750 total.
module video_timing(input clk, input rst_n,
 output reg [11:0] x, output reg [10:0] y,
 output wire de, output wire hs, output wire vs, output wire frame_tick);
 always @(posedge clk or negedge rst_n)
  if(!rst_n) begin x<=0; y<=0; end
  else if(x==1649) begin x<=0; if(y==749) y<=0; else y<=y+1'b1; end
  else x<=x+1'b1;
 assign de=(x<1280)&&(y<720);
 assign hs=(x>=1390)&&(x<1430);
 assign vs=(y>=725)&&(y<730);
 // Update during the first blank line, safely before next visible frame.
 assign frame_tick=(x==0)&&(y==720);
endmodule
