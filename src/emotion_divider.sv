// Signed / unsigned restoring divider. Truncates toward zero in 32 clocks.
module emotion_divider #(parameter WIDTH=32)(input wire clk,rst_n,start,
 input wire signed [WIDTH-1:0] numerator,input wire [15:0] denominator,
 output reg done,output reg signed [WIDTH-1:0] quotient);
 reg busy,negative;reg [$clog2(WIDTH)-1:0] count;reg [WIDTH-1:0] q;
 // Restoring division invariant: 0 <= rem < den <= 65535.
 // Only the numerator/quotient needs WIDTH bits; the remainder needs 16.
 reg [15:0] rem;reg [15:0] den;
 wire [16:0] trial={rem,q[WIDTH-1]};
 wire [WIDTH-1:0] next_q={q[WIDTH-2:0],1'b0}|{{(WIDTH-1){1'b0}},(trial>=den)};
 always @(posedge clk)begin
  if(!rst_n)begin busy<=0;done<=0;quotient<=0;q<=0;rem<=0;den<=1;count<=0;negative<=0;end
  else begin
   done<=0;
   if(start&&!busy)begin
    q<=numerator[WIDTH-1]?-numerator:numerator;negative<=numerator[WIDTH-1];
    den<=denominator==0?16'd1:denominator;rem<=0;count<=0;busy<=1;
   end else if(busy)begin
    rem<=trial>=den?trial-den:trial;q<=next_q;
    if(count==WIDTH-1)begin busy<=0;done<=1;quotient<=negative?-$signed(next_q):$signed(next_q);end
    else count<=count+1'b1;
   end
  end
 end
endmodule
