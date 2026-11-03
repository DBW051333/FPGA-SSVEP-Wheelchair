// Dedicated tensor-RAM matrix multiplier. Left operand stays resident;
// the right operand streams through port B while completed dot products use A.
module ssvep_matrix_mac(
 input wire clk,rst_n,start,transpose_b,input wire [3:0] left_bank,right_bank,destination_bank,
 output logic done,fault,
 output logic [7:0] aa,ab,output logic wea,web,output logic signed [63:0] da,db,
 input wire signed [63:0] qa,qb,
 output wire product_valid,output wire signed [63:0] product_a,product_b,
 input wire product_done,input wire signed [127:0] product);
 typedef enum logic [2:0] {IDLE,LOAD_REQ,LOAD_GET,STREAM,DRAIN,FINISH} state_t;
 state_t state;
 logic [3:0] left_id,right_id,out_id,load_index;
 logic transpose,read_pending;
 logic [5:0] issued,received;
 logic signed [63:0] left_cache[0:15],left_pending;
 logic signed [127:0] accumulator;
 wire signed [127:0] base=received[1:0]==0?128'sd0:accumulator;
 wire signed [128:0] wide_sum={base[127],base}+{product[127],product};
 wire signed [127:0] shifted=$signed(wide_sum[127:0])>>>28;
 assign product_valid=read_pending;
 assign product_a=left_pending;assign product_b=qb;
 always_comb begin
  aa={left_id,load_index};ab={right_id,4'd0};wea=0;web=0;da=0;db=0;
  if(state==STREAM)ab={right_id,transpose?{issued[3:2],issued[1:0]}:{issued[1:0],issued[3:2]}};
  if(product_done&&(state==STREAM||state==DRAIN)&&received[1:0]==3)begin
   aa={out_id,received[5:2]};wea=1;da=shifted[63:0];
  end
 end
 always_ff @(posedge clk)begin
  if(!rst_n)begin
   state<=IDLE;done<=0;fault<=0;left_id<=0;right_id<=0;out_id<=0;load_index<=0;
   issued<=0;received<=0;accumulator<=0;transpose<=0;read_pending<=0;
  end else begin
   done<=0;read_pending<=state==STREAM;
   if(state==STREAM)left_pending<=left_cache[{issued[5:4],issued[1:0]}];
   case(state)
    IDLE:if(start)begin
     left_id<=left_bank;right_id<=right_bank;out_id<=destination_bank;transpose<=transpose_b;
     load_index<=0;issued<=0;received<=0;accumulator<=0;fault<=0;
     if(destination_bank==right_bank)begin fault<=1;state<=FINISH;end else state<=LOAD_REQ;
    end
    LOAD_REQ:state<=LOAD_GET;
    LOAD_GET:begin
     left_cache[load_index]<=qa;
     if(load_index==15)state<=STREAM;else begin load_index<=load_index+1'b1;state<=LOAD_REQ;end
    end
    STREAM:begin issued<=issued+1'b1;if(issued==63)state<=DRAIN;end
    DRAIN:;
    FINISH:begin done<=1;state<=IDLE;end
    default:begin fault<=1;state<=FINISH;end
   endcase
   if(product_done&&(state==STREAM||state==DRAIN))begin
    received<=received+1'b1;accumulator<=wide_sum[127:0];
    if(received[1:0]==3&&shifted!=$signed({{64{shifted[63]}},shifted[63:0]}))fault<=1;
    if(wide_sum[128]!=wide_sum[127])fault<=1;
    if(received==63)state<=FINISH;
   end
  end
 end
endmodule
