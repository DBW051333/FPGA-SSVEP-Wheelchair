module key_filter #(parameter DEBOUNCE_CYCLES=1485000)(
 input clk,input rst_n,input key_n,output reg press);
 (* syn_preserve=1 *) reg sync1,sync2;
 reg stable; reg [21:0] count;
 always @(posedge clk or negedge rst_n)
  if(!rst_n) begin sync1<=1;sync2<=1;stable<=1;count<=0;press<=0;end
  else begin
   sync1<=key_n; sync2<=sync1; press<=0;
   if(sync2==stable) count<=0;
   else if(count==DEBOUNCE_CYCLES-1) begin
    stable<=sync2;count<=0; if(!sync2) press<=1;
   end else count<=count+1'b1;
  end
endmodule
