// 60 Hz frame-locked sine luminance. Order: up/down/left/right/center.
module ssvep_stimulus(input clk,rst_n,frame_tick,output [4:0] bright,output wire [39:0] luminance);
 function automatic [7:0] sine_level(input [5:0] p);
  begin case(p)
   6'd0:sine_level=8'd128;
   6'd1:sine_level=8'd141;
   6'd2:sine_level=8'd154;
   6'd3:sine_level=8'd167;
   6'd4:sine_level=8'd179;
   6'd5:sine_level=8'd191;
   6'd6:sine_level=8'd202;
   6'd7:sine_level=8'd213;
   6'd8:sine_level=8'd222;
   6'd9:sine_level=8'd231;
   6'd10:sine_level=8'd238;
   6'd11:sine_level=8'd244;
   6'd12:sine_level=8'd249;
   6'd13:sine_level=8'd252;
   6'd14:sine_level=8'd254;
   6'd15:sine_level=8'd255;
   6'd16:sine_level=8'd254;
   6'd17:sine_level=8'd252;
   6'd18:sine_level=8'd249;
   6'd19:sine_level=8'd244;
   6'd20:sine_level=8'd238;
   6'd21:sine_level=8'd231;
   6'd22:sine_level=8'd222;
   6'd23:sine_level=8'd213;
   6'd24:sine_level=8'd202;
   6'd25:sine_level=8'd191;
   6'd26:sine_level=8'd179;
   6'd27:sine_level=8'd167;
   6'd28:sine_level=8'd154;
   6'd29:sine_level=8'd141;
   6'd30:sine_level=8'd128;
   6'd31:sine_level=8'd114;
   6'd32:sine_level=8'd101;
   6'd33:sine_level=8'd88;
   6'd34:sine_level=8'd76;
   6'd35:sine_level=8'd64;
   6'd36:sine_level=8'd53;
   6'd37:sine_level=8'd42;
   6'd38:sine_level=8'd33;
   6'd39:sine_level=8'd24;
   6'd40:sine_level=8'd17;
   6'd41:sine_level=8'd11;
   6'd42:sine_level=8'd6;
   6'd43:sine_level=8'd3;
   6'd44:sine_level=8'd1;
   6'd45:sine_level=8'd0;
   6'd46:sine_level=8'd1;
   6'd47:sine_level=8'd3;
   6'd48:sine_level=8'd6;
   6'd49:sine_level=8'd11;
   6'd50:sine_level=8'd17;
   6'd51:sine_level=8'd24;
   6'd52:sine_level=8'd33;
   6'd53:sine_level=8'd42;
   6'd54:sine_level=8'd53;
   6'd55:sine_level=8'd64;
   6'd56:sine_level=8'd76;
   6'd57:sine_level=8'd88;
   6'd58:sine_level=8'd101;
   6'd59:sine_level=8'd114;
   default:sine_level=8'd128;
  endcase end
 endfunction
 reg [5:0] phase[0:4];integer i;integer step;
 always @(posedge clk or negedge rst_n)
  if(!rst_n)for(i=0;i<5;i=i+1)phase[i]<=0;
  else if(frame_tick)for(i=0;i<5;i=i+1)begin
   case(i)0:step=7;1:step=9;2:step=11;3:step=15;default:step=17;endcase
   if(phase[i]+step>=60)phase[i]<=phase[i]+step-60;else phase[i]<=phase[i]+step;
  end
 genvar n;generate for(n=0;n<5;n=n+1)begin:b
  assign bright[n]=phase[n]<30;
  assign luminance[n*8+:8]=sine_level(phase[n]);
 end endgenerate
endmodule
