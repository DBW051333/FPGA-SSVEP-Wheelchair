// Eight active electrodes: Cyton 1..4 followed by Daisy 9..12.
// Reuses the same decoded UART bytes as SSVEP; never adds a second UART driver.
module emotion_rx8 #(parameter CLOCK_HZ=27000000)(
 input wire clk,rst_n,byte_valid,byte_error,input wire [7:0] byte_data,
 output reg sample_valid,output reg [255:0] samples,
 output reg discontinuity,output reg [15:0] sequence_number);
 reg [5:0] pos;reg [7:0] packet_id,even_id,last_even;
 reg [23:0] assembled[0:3],daisy[0:3];
 reg have_even,have_sequence,seen_packet;reg [31:0] timer;integer i;
 function automatic signed [31:0] uv(input [23:0] raw);
  reg signed [55:0] prod;
  begin prod=$signed(raw)*56'sd96000011;uv=(prod+56'sd8388608)>>>24;end
 endfunction
 always @(posedge clk)begin
  if(!rst_n)begin
   pos<=0;packet_id<=0;even_id<=0;last_even<=0;timer<=0;
   have_even<=0;have_sequence<=0;seen_packet<=0;sample_valid<=0;discontinuity<=0;
   samples<=0;sequence_number<=0;
   for(i=0;i<4;i=i+1)begin assembled[i]<=0;daisy[i]<=0;end
  end else begin
   sample_valid<=0;discontinuity<=0;
   if(timer<CLOCK_HZ/2)timer<=timer+1'b1;
   if(byte_error||timer>=CLOCK_HZ/2)begin
    if(have_even||have_sequence||pos!=0)discontinuity<=1;
    pos<=0;have_even<=0;have_sequence<=0;timer<=0;
   end else if(byte_valid)begin
    timer<=0;
    if(pos==0)begin if(byte_data==8'ha0)pos<=1;end
    else if(pos==1)begin packet_id<=byte_data;pos<=2;end
    else if(pos<32)begin
     if(pos>=2&&pos<=13)case(pos)
      2,3,4:assembled[0]<={assembled[0][15:0],byte_data};
      5,6,7:assembled[1]<={assembled[1][15:0],byte_data};
      8,9,10:assembled[2]<={assembled[2][15:0],byte_data};
      11,12,13:assembled[3]<={assembled[3][15:0],byte_data};
      default:;
     endcase
     pos<=pos+1'b1;
    end else begin
     pos<=0;
     if(byte_data<8'hc0||byte_data>8'hc6)begin
      have_even<=0;have_sequence<=0;discontinuity<=1;
      if(byte_data==8'ha0)pos<=1;
     end else if(!packet_id[0])begin
      seen_packet<=1;even_id<=packet_id;have_even<=seen_packet||packet_id!=0;
      for(i=0;i<4;i=i+1)daisy[i]<=assembled[i];
     end else begin
      have_even<=0;seen_packet<=1;
      if(have_even&&packet_id==even_id+8'd1)begin
       for(i=0;i<4;i=i+1)begin
        samples[i*32+:32]<=uv(assembled[i]);
        samples[(i+4)*32+:32]<=uv(daisy[i]);
       end
       sample_valid<=1;
       if(have_sequence&&even_id!=last_even+8'd2)discontinuity<=1;
       last_even<=even_id;have_sequence<=1;
       sequence_number<=have_sequence?sequence_number+{9'd0,((even_id-last_even)>>1)}:16'd0;
      end else begin have_sequence<=0;discontinuity<=1;end
     end
    end
   end
  end
 end
endmodule
