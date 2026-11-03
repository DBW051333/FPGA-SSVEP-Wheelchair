// DVI video over HDMI connector: RGB888, no audio, LSB-first TMDS.
module tmds_encode(input clk,input rst_n,input [7:0] data,input de,
 input c0,input c1,output reg [9:0] symbol);
 reg [8:0] qm; reg [9:0] encoded;
 reg signed [5:0] disparity,next_disparity;
 integer ones,balance,j;
 reg use_xnor;
 always @* begin
  ones=0; for(j=0;j<8;j=j+1) ones=ones+data[j];
  use_xnor=(ones>4)||((ones==4)&&!data[0]);
  qm[0]=data[0];
  for(j=1;j<8;j=j+1) qm[j]=qm[j-1]^data[j]^use_xnor;
  qm[8]=!use_xnor;
  ones=0; for(j=0;j<8;j=j+1) ones=ones+qm[j];
  balance=2*ones-8;
  encoded=0;next_disparity=disparity;
  if(!de) begin
   next_disparity=0;
   case({c1,c0})
    0:encoded=10'b1101010100;1:encoded=10'b0010101011;
    2:encoded=10'b0101010100;3:encoded=10'b1010101011;
   endcase
  end else if((disparity==0)||(balance==0)) begin
   encoded={~qm[8],qm[8],qm[8]?qm[7:0]:~qm[7:0]};
   next_disparity=disparity+(qm[8]?balance:-balance);
  end else if(((disparity>0)&&(balance>0))||((disparity<0)&&(balance<0))) begin
   encoded={1'b1,qm[8],~qm[7:0]};
   next_disparity=disparity+2*qm[8]-balance;
  end else begin
   encoded={1'b0,qm[8],qm[7:0]};
   next_disparity=disparity-2*(!qm[8])+balance;
  end
 end
 always @(posedge clk or negedge rst_n)
  if(!rst_n) begin symbol<=10'b1101010100;disparity<=0;end
  else begin symbol<=encoded;disparity<=next_disparity;end
endmodule

// Dedicated I/O serializer. No 371.25 MHz fabric shift registers or word counter.
module tmds_lane(input pclk,input fclk,input reset,input [9:0] word,
 output positive,output negative);
 wire serial;
 OSER10 ser(.D0(word[0]),.D1(word[1]),.D2(word[2]),.D3(word[3]),.D4(word[4]),
  .D5(word[5]),.D6(word[6]),.D7(word[7]),.D8(word[8]),.D9(word[9]),
  .PCLK(pclk),.FCLK(fclk),.RESET(reset),.Q(serial));
 // LVPECL33E/DRIVE=8 selects complementary 3.3 V CMOS outputs in this Bank.
 // The existing board HDMI termination network still requires physical validation.
 ELVDS_OBUF ob(.I(serial),.O(positive),.OB(negative));
endmodule

module tmds_tx(input pclk,input fclk,input rst_n,input [23:0] rgb,
 input hs,input vs,input de,output clk_p,output clk_n,output [2:0] data_p,output [2:0] data_n,
 input serializer_reset);
 wire [9:0] r,g,b;
 tmds_encode er(pclk,rst_n,rgb[23:16],de,1'b0,1'b0,r);
 tmds_encode eg(pclk,rst_n,rgb[15:8],de,1'b0,1'b0,g);
 tmds_encode eb(pclk,rst_n,rgb[7:0],de,hs,vs,b);
 tmds_lane lr(pclk,fclk,serializer_reset,r,data_p[2],data_n[2]);
 tmds_lane lg(pclk,fclk,serializer_reset,g,data_p[1],data_n[1]);
 tmds_lane lb(pclk,fclk,serializer_reset,b,data_p[0],data_n[0]);
 tmds_lane lc(pclk,fclk,serializer_reset,10'b1111100000,clk_p,clk_n);
endmodule
