// Actual panel feedback only; highest lit LED defines the original panel level.
module panel_status(input wire [11:0] leds,input wire direct_valid,serial_valid,
 output reg [23:0] status);
 integer i;
 always @* begin
  status=24'd0;status[4:2]=3'd5; // emotion disabled
  status[15:14]=leds[11:10];status[19:18]={2{direct_valid}};
  for(i=0;i<5;i=i+1)begin
   if(serial_valid && leds[i])begin status[13:11]=i+1;status[17]=1;end
   if(serial_valid && direct_valid && leds[i+5])begin status[10:8]=i+1;status[16]=1;end
  end
 end
endmodule
