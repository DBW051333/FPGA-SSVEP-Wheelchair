`include "ssvep_hardware_layout.vh"
// Fixed EEG signal-processing hardware. No program ROM, PC, ISA or register file.
module ssvep_hardware_core(
 input wire clk,rst_n,sample_valid,output wire sample_ready,
 input wire signed [31:0] sample0,sample1,sample2,sample3,input wire [3:0] sample_bad,
 input wire sample_reset,sample_active,sample_method,input wire [15:0] sample_epoch,sample_sequence,
 output logic check_valid,output logic signed [63:0] score0,score1,score2,score3,score4,
 output logic [3:0] channel_mask,output logic [15:0] check_epoch,check_sequence,
 output logic numeric_fault,output wire [15:0] debug_phase,output logic [31:0] cycle_counter);
 logic [2:0] owner;
 logic [8:0] write_pointer,accepted_count,hop_count,window_start,ring_index,index;
 logic [1:0] channel,row,col,inner;
 logic [3:0] matrix_index;
 logic [2:0] band,target,good_count;
 logic [6:0] covariance_lag;
 logic frame_active,frame_method,history_skip;
 logic [15:0] frame_epoch,frame_sequence;
 logic [3:0] initialized,frame_good,good_mask;
 logic [8:0] bad_count[0:3],history_bad[0:3];
 logic [255:0] pre_samples,clean_samples;
 wire signed [63:0] raw_input[0:3];
 assign raw_input[0]=$signed({{32{sample0[31]}},sample0})<<<20;
 assign raw_input[1]=$signed({{32{sample1[31]}},sample1})<<<20;
 assign raw_input[2]=$signed({{32{sample2[31]}},sample2})<<<20;
 assign raw_input[3]=$signed({{32{sample3[31]}},sample3})<<<20;
 wire [3:0] input_good;
 genvar g;
 generate for(g=0;g<4;g=g+1)begin:ingress_quality
  assign input_good[g]=!sample_bad[g]&&raw_input[g]<64'sd40265318400000&&raw_input[g]>-64'sd40265318400000;
 end endgenerate
 logic signed [63:0] analysis_mean[0:3],bank_mean[0:3],scores[0:4];
 logic signed [63:0] inverse[0:3];
 logic signed [63:0] sample_value,sum_value,range_min,range_max,mean_value,peak_range;
 logic signed [63:0] square_mean,variance,covariance,covariance_sum,lag_weight,weighted_covariance;
 logic signed [63:0] trace_value,scale_value,root_scale,regularizer,cutoff,eigen_max;
 logic signed [63:0] term,term_scaled,whiten_sum,candidate_max,band_weight,weighted_score;
 wire local_covariance=frame_method&&band==0;
 wire [13:0] channel_ring=14'(channel*375),channel_window=14'(channel*312),channel_band=14'(channel*250);
 wire [13:0] row_band=14'(row*250),col_band=14'(col*250);
 wire [13:0] template_base=({11'd0,target}<<9)-({11'd0,target}<<3)-({11'd0,target}<<2)+14'(col*125);
 logic [13:0] ram_a,ram_b;logic ram_we;logic signed [63:0] ram_wd;
 wire signed [63:0] ram_qa,ram_qb;
 logic [13:0] memory_a,memory_b;logic memory_we;logic signed [63:0] memory_wd;
 wire [13:0] filter_a,filter_b,vector_a,vector_b;
 wire filter_we;wire signed [63:0] filter_wd;
 ssvep_data_ram #(.COMPACT_BAD(1)) storage(clk,memory_we,memory_a,memory_a,memory_b,memory_wd,ram_qa,ram_qb);
 always_comb begin
  memory_a=ram_a;memory_b=ram_b;memory_we=ram_we;memory_wd=ram_wd;
  if(owner==1)begin memory_a=filter_a;memory_b=filter_b;memory_we=filter_we;memory_wd=filter_wd;end
  if(owner==2)begin memory_a=vector_a;memory_b=vector_b;memory_we=0;memory_wd=0;end
 end
 logic filter_start,filter_window;
 wire filter_done,filter_fault;wire [255:0] filter_result;
 wire filter_product;wire signed [63:0] filter_pa,filter_pb;
 logic vector_start,vector_periodic;
 logic [13:0] vector_source_a,vector_source_b;
 logic [15:0] vector_length,vector_denominator;
 logic [6:0] vector_lag;
 wire vector_done,vector_fault;wire signed [63:0] vector_value;
 wire vector_product;wire signed [63:0] vector_pa,vector_pb;
 wire [11:0] reference_a,reference_b;wire signed [63:0] reference_qa,reference_qb;
 wire vector_divide;wire signed [127:0] vector_numerator;wire signed [63:0] vector_divisor;
 logic matrix_start,matrix_transpose;logic [1:0] matrix_pass;
 wire matrix_done,matrix_fault,matrix_product;wire signed [63:0] matrix_pa,matrix_pb;
 wire [3:0] left_bank=matrix_pass==0?4'd2:matrix_pass==1?4'd4:4'd5;
 wire [3:0] right_bank=matrix_pass==0?4'd1:matrix_pass==1?4'd3:4'd5;
 wire [3:0] destination_bank=matrix_pass==0?4'd4:matrix_pass==1?4'd5:4'd6;
 logic eigen_start,eigen_keep_vectors;
 wire eigen_done,eigen_fault;
 wire eigen_math_request;wire [1:0] eigen_math_kind;wire signed [63:0] eigen_math_a,eigen_math_b;
 logic [7:0] tensor_a,tensor_b;logic tensor_wea,tensor_web;logic signed [63:0] tensor_da,tensor_db;
 wire signed [63:0] tensor_qa,tensor_qb;
 wire [7:0] matrix_ta,matrix_tb,eigen_ta,eigen_tb;
 wire matrix_twea,matrix_tweb,eigen_twea,eigen_tweb;
 wire signed [63:0] matrix_tda,matrix_tdb,eigen_tda,eigen_tdb;
 logic [7:0] tensor_mux_a,tensor_mux_b;logic tensor_mux_wea,tensor_mux_web;
 logic signed [63:0] tensor_mux_da,tensor_mux_db;
 always_comb begin
  tensor_mux_a=tensor_a;tensor_mux_b=tensor_b;tensor_mux_wea=tensor_wea;tensor_mux_web=tensor_web;
  tensor_mux_da=tensor_da;tensor_mux_db=tensor_db;
  if(owner==3)begin
   tensor_mux_a=matrix_ta;tensor_mux_b=matrix_tb;tensor_mux_wea=matrix_twea;tensor_mux_web=matrix_tweb;
   tensor_mux_da=matrix_tda;tensor_mux_db=matrix_tdb;
  end
  if(owner==4)begin
   tensor_mux_a=eigen_ta;tensor_mux_b=eigen_tb;tensor_mux_wea=eigen_twea;tensor_mux_web=eigen_tweb;
   tensor_mux_da=eigen_tda;tensor_mux_db=eigen_tdb;
  end
 end
 ssvep_tensor_ram tensor_storage(clk,tensor_mux_wea&&rst_n,tensor_mux_web&&rst_n,tensor_mux_a,tensor_mux_b,
  tensor_mux_da,tensor_mux_db,tensor_qa,tensor_qb);
 logic math_request;logic [1:0] math_kind;logic signed [63:0] math_a,math_b;
 wire math_response,math_error;wire signed [63:0] math_value;
 wire arithmetic_response,arithmetic_error;wire signed [63:0] arithmetic_value;
 logic product_valid;logic signed [63:0] product_a,product_b;
 wire product_done,product_overflow;wire signed [127:0] product;wire signed [63:0] rounded_product;
 logic divide_start;logic [2:0] divide_op;logic signed [63:0] divide_a,divide_b;
 logic signed [127:0] divide_wide;
 wire divide_busy,divide_done,divide_error;wire signed [63:0] divide_value;wire signed [127:0] unused_product;
 ssvep_product_pipe multiplier(clk,rst_n,product_valid,product_a,product_b,product_done,product,rounded_product,product_overflow);
 qmath #(.ENABLE_MULTIPLY(0),.FAST_DIVIDE(1),.RADIX4_DIVIDE(1)) divider_root(clk,rst_n,divide_start,divide_op,divide_a,divide_b,divide_wide,
  divide_busy,divide_done,divide_error,divide_value,unused_product);
 assign arithmetic_response=product_done||divide_done;
 assign arithmetic_value=product_done?rounded_product:divide_value;
 assign arithmetic_error=product_done?product_overflow:divide_error;
 assign math_response=owner==0&&arithmetic_response;
 assign math_value=arithmetic_value;assign math_error=arithmetic_error;
 always_comb begin
  product_valid=0;product_a=0;product_b=0;
  divide_start=0;divide_op=1;divide_a=0;divide_b=0;divide_wide=0;
  case(owner)
   0:begin
    product_valid=math_request&&math_kind==0;product_a=math_a;product_b=math_b;
    divide_start=math_request&&math_kind!=0;divide_op=math_kind==2?3'd2:3'd1;divide_a=math_a;divide_b=math_b;
   end
   1:begin product_valid=filter_product;product_a=filter_pa;product_b=filter_pb;end
   2:begin
    product_valid=vector_product;product_a=vector_pa;product_b=vector_pb;
    divide_start=vector_divide;divide_op=4;divide_wide=vector_numerator;divide_b=vector_divisor;
   end
   3:begin product_valid=matrix_product;product_a=matrix_pa;product_b=matrix_pb;end
   4:begin
    product_valid=eigen_math_request&&eigen_math_kind==0;product_a=eigen_math_a;product_b=eigen_math_b;
    divide_start=eigen_math_request&&eigen_math_kind!=0;divide_op=eigen_math_kind==2?3'd2:3'd1;
    divide_a=eigen_math_a;divide_b=eigen_math_b;
   end
   default:;
  endcase
 end
 ssvep_batch_sos filter(clk,rst_n,filter_start,filter_window,history_skip,band,
  ~initialized|~frame_good,pre_samples,filter_done,filter_fault,filter_result,
  filter_a,filter_b,filter_we,filter_wd,ram_qa,ram_qb,filter_product,filter_pa,filter_pb,
  product_done&&owner==1,product_overflow,rounded_product);
 ssvep_reference_rom reference_table(clk,reference_a,reference_b,reference_qa,reference_qb);
 ssvep_vector_mac covariance_pipeline(clk,rst_n,vector_start,vector_periodic,vector_source_a,vector_source_b,
  vector_length,vector_denominator,vector_lag,vector_done,vector_fault,vector_value,
  vector_a,vector_b,ram_qa,ram_qb,reference_a,reference_b,reference_qa,reference_qb,
  vector_product,vector_pa,vector_pb,product_done&&owner==2,product,
  vector_divide,vector_numerator,vector_divisor,divide_done&&owner==2,divide_error,divide_value);
 ssvep_matrix_mac matrix_pipeline(clk,rst_n,matrix_start,matrix_transpose,left_bank,right_bank,destination_bank,
  matrix_done,matrix_fault,matrix_ta,matrix_tb,matrix_twea,matrix_tweb,matrix_tda,matrix_tdb,tensor_qa,tensor_qb,
  matrix_product,matrix_pa,matrix_pb,product_done&&owner==3,product);
 ssvep_jacobi tensor_solver(clk,rst_n,eigen_start,eigen_keep_vectors,eigen_done,eigen_fault,
  eigen_ta,eigen_tb,eigen_twea,eigen_tweb,eigen_tda,eigen_tdb,tensor_qa,tensor_qb,
  eigen_math_request,eigen_math_kind,eigen_math_a,eigen_math_b,arithmetic_response&&owner==4,arithmetic_error,arithmetic_value);
 logic signed [63:0] add_a,add_b;logic add_sub;
 wire signed [64:0] add_result=add_sub?({add_a[63],add_a}-{add_b[63],add_b}):({add_a[63],add_a}+{add_b[63],add_b});
localparam integer HARDWARE_STATES=230;
typedef enum logic [15:0] {H0,H1,H2,H3,H4,H5,H6,H7,H8,H9,H10,H11,H12,H13,H14,H15,H16,H17,H18,H19,H20,H21,H22,H23,H24,H25,H26,H27,H28,H29,H30,H31,H32,H33,H34,H35,H36,H37,H38,H39,H40,H41,H42,H43,H44,H45,H46,H47,H48,H49,H50,H51,H52,H53,H54,H55,H56,H57,H58,H59,H60,H61,H62,H63,H64,H65,H66,H67,H68,H69,H70,H71,H72,H73,H74,H75,H76,H77,H78,H79,H80,H81,H82,H83,H84,H85,H86,H87,H88,H89,H90,H91,H92,H93,H94,H95,H96,H97,H98,H99,H100,H101,H102,H103,H104,H105,H106,H107,H108,H109,H110,H111,H112,H113,H114,H115,H116,H117,H118,H119,H120,H121,H122,H123,H124,H125,H126,H127,H128,H129,H130,H131,H132,H133,H134,H135,H136,H137,H138,H139,H140,H141,H142,H143,H144,H145,H146,H147,H148,H149,H150,H151,H152,H153,H154,H155,H156,H157,H158,H159,H160,H161,H162,H163,H164,H165,H166,H167,H168,H169,H170,H171,H172,H173,H174,H175,H176,H177,H178,H179,H180,H181,H182,H183,H184,H185,H186,H187,H188,H189,H190,H191,H192,H193,H194,H195,H196,H197,H198,H199,H200,H201,H202,H203,H204,H205,H206,H207,H208,H209,H210,H211,H212,H213,H214,H215,H216,H217,H218,H219,H220,H221,H222,H223,H224,H225,H226,H227,H228,H229} state_t;
state_t state;
always_comb begin
ram_a=0;ram_b=0;ram_we=0;ram_wd=0;
filter_start=0;filter_window=0;vector_start=0;matrix_start=0;matrix_transpose=0;eigen_start=0;
math_request=0;math_kind=0;math_a=0;math_b=0;add_a=0;add_b=0;add_sub=0;
tensor_a=0;tensor_b=0;tensor_wea=0;tensor_web=0;tensor_da=0;tensor_db=0;
case(state)
H2:begin filter_start=1;filter_window=0; end
H6:begin ram_a=`HW_CLEAN+channel_ring+{5'd0,write_pointer};ram_we=1;ram_wd=$signed(clean_samples[(3-channel)*64+:64]); end
H7:begin ram_a=`HW_BAD+channel_ring+{5'd0,write_pointer};ram_we=1;ram_wd={63'd0,!frame_good[channel]}; end
H22:begin ram_a=`HW_CLEAN+channel_ring+{5'd0,ring_index}; end
H24:begin ram_a=`HW_X+channel_window+{5'd0,index};ram_we=1;ram_wd=sample_value; end
H25:begin ram_a=`HW_BAD+channel_ring+{5'd0,ring_index}; end
H31:begin ram_a=`HW_X+channel_window+14'd62+{5'd0,index}; end
H32:begin add_a=sum_value;add_b=ram_qa; end
H33:begin math_request=1;math_kind=2'd1;math_a=sum_value;math_b=64'sd67108864000; end
H36:begin add_a=range_max;add_b=range_min;add_sub=1; end
H38:begin vector_start=1; end
H41:begin math_request=1;math_kind=2'd0;math_a=mean_value;math_b=mean_value; end
H43:begin add_a=covariance;add_b=square_mean;add_sub=1; end
H47:begin ram_a=`HW_X+channel_window+{5'd0,index}; end
H48:begin add_a=ram_qa;add_b=analysis_mean[channel];add_sub=1; end
H49:begin ram_a=`HW_X+channel_window+{5'd0,index};ram_we=1;ram_wd=sample_value; end
H57:begin filter_start=1;filter_window=1; end
H62:begin ram_a=`HW_XB+channel_band+{5'd0,index}; end
H63:begin add_a=sum_value;add_b=ram_qa; end
H64:begin math_request=1;math_kind=2'd1;math_a=sum_value;math_b=64'sd67108864000; end
H73:begin vector_start=1; end
H77:begin ram_a=`HW_TRI+{7'd0,covariance_lag}-14'd1; end
H79:begin math_request=1;math_kind=2'd0;math_a=covariance;math_b=lag_weight; end
H81:begin add_a=covariance_sum;add_b=weighted_covariance;add_sub=0; end
H86:begin math_request=1;math_kind=2'd0;math_a=bank_mean[row];math_b=bank_mean[col]; end
H88:begin add_a=covariance;add_b=square_mean;add_sub=1; end
H91:begin tensor_a=8'h00+{4'd0,row,col};tensor_wea=1;tensor_da=covariance;tensor_b=8'h00+{4'd0,col,row};tensor_web=row!=col;tensor_db=covariance; end
H97:begin tensor_a=8'h00+{4'd0,inner,inner};tensor_b=8'd0; end
H99:begin add_a=trace_value;add_b=term;add_sub=0; end
H102:begin math_request=1;math_kind=2'd1;math_a=trace_value;math_b=$signed({33'd0,good_count,28'd0}); end
H105:begin math_request=1;math_kind=2'd2;math_a=scale_value;math_b=64'sd0; end
H108:begin tensor_a=8'h00+{4'd0,matrix_index};tensor_b=8'd0; end
H110:begin math_request=1;math_kind=2'd1;math_a=term;math_b=scale_value; end
H113:begin add_a=term;add_b=64'sd268;add_sub=0; end
H114:begin tensor_a=8'h60+{4'd0,matrix_index};tensor_wea=1;tensor_da=term; end
H118:begin eigen_start=1; end
H121:begin math_request=1;math_kind=2'd1;math_a=64'sd268435456;math_b=scale_value; end
H124:begin tensor_a=8'h60+{4'd0,inner,inner};tensor_b=8'd0; end
H129:begin math_request=1;math_kind=2'd0;math_a=eigen_max;math_b=64'sd268; end
H132:begin tensor_a=8'h60+{4'd0,inner,inner};tensor_b=8'd0; end
H135:begin math_request=1;math_kind=2'd2;math_a=term;math_b=64'sd0; end
H137:begin math_request=1;math_kind=2'd1;math_a=64'sd268435456;math_b=term; end
H144:begin tensor_a=8'h70+{4'd0,row,inner};tensor_b=8'h70+{4'd0,col,inner}; end
H145:begin math_request=1;math_kind=2'd0;math_a=tensor_qa;math_b=tensor_qb; end
H147:begin math_request=1;math_kind=2'd0;math_a=term;math_b=inverse[inner]; end
H149:begin add_a=whiten_sum;add_b=term_scaled;add_sub=0; end
H152:begin tensor_a=8'h20+{4'd0,row,col};tensor_wea=1;tensor_da=whiten_sum;tensor_b=8'h20+{4'd0,col,row};tensor_web=row!=col;tensor_db=whiten_sum; end
H162:begin vector_start=1; end
H166:begin ram_a=`HW_TRI+{7'd0,covariance_lag}-14'd1; end
H168:begin math_request=1;math_kind=2'd0;math_a=covariance;math_b=lag_weight; end
H170:begin add_a=covariance_sum;add_b=weighted_covariance;add_sub=0; end
H176:begin tensor_a=8'h10+{4'd0,row,col};tensor_wea=1;tensor_da=covariance; end
H182:begin ram_a=`HW_YWHITEN+(local_covariance?14'd80:14'd0)+{7'd0,target,4'd0}+{10'd0,matrix_index}; end
H184:begin tensor_a=8'h30+{4'd0,matrix_index};tensor_wea=1;tensor_da=term; end
H188:begin matrix_start=1;matrix_transpose=0; end
H192:begin tensor_a=8'h40+{4'd0,matrix_index};tensor_b=8'd0; end
H194:begin math_request=1;math_kind=2'd1;math_a=term;math_b=root_scale; end
H196:begin tensor_a=8'h40+{4'd0,matrix_index};tensor_wea=1;tensor_da=term; end
H200:begin matrix_start=1;matrix_transpose=0; end
H204:begin matrix_start=1;matrix_transpose=1; end
H208:begin eigen_start=1; end
H212:begin tensor_a=8'h60+{4'd0,inner,inner};tensor_b=8'd0; end
H218:begin ram_a=`HW_WEIGHTS+(frame_method?14'd5:14'd0)+{11'd0,band}; end
H220:begin math_request=1;math_kind=2'd0;math_a=candidate_max;math_b=band_weight; end
H222:begin add_a=scores[target];add_b=weighted_score;add_sub=0; end
default:;
endcase
end
always_ff @(posedge clk)begin
if(!rst_n)begin state<=H0;
owner<=0;write_pointer<=0;accepted_count<=0;hop_count<=0;initialized<=0;frame_good<=0;good_mask<=0;
frame_active<=0;frame_method<=0;frame_epoch<=0;frame_sequence<=0;history_skip<=0;good_count<=0;
channel<=0;row<=0;col<=0;inner<=0;index<=0;matrix_index<=0;band<=0;target<=0;covariance_lag<=0;
check_valid<=0;numeric_fault<=0;score0<=0;score1<=0;score2<=0;score3<=0;score4<=0;channel_mask<=0;
check_epoch<=0;check_sequence<=0;cycle_counter<=0;
vector_source_a<=0;vector_source_b<=0;vector_periodic<=0;vector_length<=0;vector_denominator<=250;vector_lag<=0;
matrix_pass<=0;eigen_keep_vectors<=0;
end else begin
check_valid<=0;if(state!=H0)cycle_counter<=cycle_counter+1'b1;
case(state)
H0:begin if(sample_valid)begin
 frame_active<=sample_active;frame_method<=sample_method;frame_epoch<=sample_epoch;frame_sequence<=sample_sequence;
 if(sample_reset)begin accepted_count<=0;hop_count<=0;end
 frame_good<=input_good;
 for(integer z=0;z<4;z=z+1)pre_samples[(3-z)*64+:64]<=input_good[z]?raw_input[z]:64'sd0;
end
if(sample_valid)state<=H1; end
H1:begin owner<=1;
state<=H2; end
H2:begin 
state<=H3; end
H3:begin 
if(filter_done)begin if(filter_fault)state<=H229;else state<=H4;end end
H4:begin owner<=0;
state<=H5; end
H5:begin clean_samples<=filter_result;initialized<=frame_good;channel<=0;
state<=H6; end
H6:begin 
state<=H7; end
H7:begin 
state<=H8; end
H8:begin 
if(channel==3)state<=H10;else state<=H9; end
H9:begin channel<=channel+1'b1;
state<=H6; end
H10:begin write_pointer<=write_pointer==374?9'd0:write_pointer+1'b1;
state<=H11; end
H11:begin 
if(!frame_active)state<=H16;else state<=H12; end
H12:begin 
if(accepted_count==312)state<=H17;else state<=H13; end
H13:begin accepted_count<=accepted_count+1'b1;
state<=H14; end
H14:begin 
if(accepted_count==312)state<=H20;else state<=H15; end
H15:begin 
state<=H0; end
H16:begin accepted_count<=0;hop_count<=0;
state<=H0; end
H17:begin 
if(hop_count>=123)state<=H19;else state<=H18; end
H18:begin hop_count<=hop_count+9'd2;
state<=H0; end
H19:begin hop_count<=hop_count-9'd123;
state<=H20; end
H20:begin good_mask<=0;good_count<=0;history_skip<=0;channel<=0;window_start<=write_pointer>=312?write_pointer-9'd312:write_pointer+9'd63;
state<=H21; end
H21:begin index<=0;ring_index<=window_start;bad_count[channel]<=0;history_bad[channel]<=0;
state<=H22; end
H22:begin 
state<=H23; end
H23:begin sample_value<=ram_qa;
state<=H24; end
H24:begin 
state<=H25; end
H25:begin 
state<=H26; end
H26:begin sample_value<=ram_qa;
state<=H27; end
H27:begin if(index<62)history_bad[channel]<=history_bad[channel]+{8'd0,sample_value[0]};else bad_count[channel]<=bad_count[channel]+{8'd0,sample_value[0]};
state<=H28; end
H28:begin 
if(index==311)state<=H30;else state<=H29; end
H29:begin index<=index+1'b1;ring_index<=ring_index==374?9'd0:ring_index+1'b1;
state<=H22; end
H30:begin sum_value<=0;index<=0;
state<=H31; end
H31:begin 
state<=H32; end
H32:begin sum_value<=add_result[63:0];index<=index+1'b1;if(index==0||ram_qa<range_min)range_min<=ram_qa;if(index==0||ram_qa>range_max)range_max<=ram_qa;
if(add_result[64]!=add_result[63])state<=H229;else if(index==249)state<=H33;else state<=H31; end
H33:begin 
state<=H34; end
H34:begin if(math_response)begin mean_value<=math_value;end
if(math_response)begin if(math_error)state<=H229;else state<=H35;end end
H35:begin analysis_mean[channel]<=mean_value;
state<=H36; end
H36:begin peak_range<=add_result[63:0];
if(add_result[64]!=add_result[63])state<=H229;else state<=H37; end
H37:begin owner<=2;vector_source_a<=`HW_X+channel_window+14'd62;vector_source_b<=`HW_X+channel_window+14'd62;vector_periodic<=0;vector_length<=16'd250;vector_denominator<=250;vector_lag<=7'd0;
state<=H38; end
H38:begin 
state<=H39; end
H39:begin 
if(vector_done)begin if(vector_fault)state<=H229;else state<=H40;end end
H40:begin owner<=0;covariance<=vector_value;
state<=H41; end
H41:begin 
state<=H42; end
H42:begin if(math_response)begin square_mean<=math_value;end
if(math_response)begin if(math_error)state<=H229;else state<=H43;end end
H43:begin variance<=add_result[63:0];
if(add_result[64]!=add_result[63])state<=H229;else state<=H44; end
H44:begin 
if(bad_count[channel]!=0||variance<64'sd107374||variance>64'sd6710886400000000||peak_range>64'sd5368709120000)state<=H46;else state<=H45; end
H45:begin good_mask[channel]<=1;good_count<=good_count+1'b1;if(history_bad[channel]!=0)history_skip<=1;
state<=H46; end
H46:begin index<=0;
state<=H47; end
H47:begin 
state<=H48; end
H48:begin sample_value<=add_result[63:0];
if(add_result[64]!=add_result[63])state<=H229;else state<=H49; end
H49:begin 
state<=H50; end
H50:begin 
if(index==311)state<=H52;else state<=H51; end
H51:begin index<=index+1'b1;
state<=H47; end
H52:begin 
if(channel==3)state<=H54;else state<=H53; end
H53:begin channel<=channel+1'b1;
state<=H21; end
H54:begin 
if(good_count<2)state<=H228;else state<=H55; end
H55:begin for(integer z=0;z<5;z=z+1)scores[z]<=0;band<=0;
state<=H56; end
H56:begin owner<=1;
state<=H57; end
H57:begin 
state<=H58; end
H58:begin 
if(filter_done)begin if(filter_fault)state<=H229;else state<=H59;end end
H59:begin owner<=0;
state<=H60; end
H60:begin channel<=0;
state<=H61; end
H61:begin sum_value<=0;index<=0;
state<=H62; end
H62:begin 
state<=H63; end
H63:begin sum_value<=add_result[63:0];index<=index+1'b1;
if(add_result[64]!=add_result[63])state<=H229;else if(index==249)state<=H64;else state<=H62; end
H64:begin 
state<=H65; end
H65:begin if(math_response)begin mean_value<=math_value;end
if(math_response)begin if(math_error)state<=H229;else state<=H66;end end
H66:begin bank_mean[channel]<=mean_value;
state<=H67; end
H67:begin 
if(channel==3)state<=H69;else state<=H68; end
H68:begin channel<=channel+1'b1;
state<=H61; end
H69:begin row<=0;col<=0;
state<=H70; end
H70:begin 
if(!good_mask[row]||!good_mask[col])state<=H90;else state<=H71; end
H71:begin covariance_sum<=0;covariance_lag<=local_covariance?7'd1:7'd0;
state<=H72; end
H72:begin owner<=2;vector_source_a<=`HW_XB+row_band;vector_source_b<=`HW_XB+col_band;vector_periodic<=0;vector_length<=16'd250-{9'd0,covariance_lag};vector_denominator<=250;vector_lag<=covariance_lag;
state<=H73; end
H73:begin 
state<=H74; end
H74:begin 
if(vector_done)begin if(vector_fault)state<=H229;else state<=H75;end end
H75:begin owner<=0;covariance<=vector_value;
state<=H76; end
H76:begin 
if(!local_covariance)state<=H85;else state<=H77; end
H77:begin 
state<=H78; end
H78:begin lag_weight<=ram_qa;
state<=H79; end
H79:begin 
state<=H80; end
H80:begin if(math_response)begin weighted_covariance<=math_value;end
if(math_response)begin if(math_error)state<=H229;else state<=H81;end end
H81:begin covariance_sum<=add_result[63:0];
if(add_result[64]!=add_result[63])state<=H229;else state<=H82; end
H82:begin 
if(covariance_lag==11)state<=H84;else state<=H83; end
H83:begin covariance_lag<=covariance_lag+1'b1;
state<=H72; end
H84:begin covariance<=covariance_sum;
state<=H85; end
H85:begin 
if(local_covariance)state<=H91;else state<=H86; end
H86:begin 
state<=H87; end
H87:begin if(math_response)begin square_mean<=math_value;end
if(math_response)begin if(math_error)state<=H229;else state<=H88;end end
H88:begin covariance<=add_result[63:0];
if(add_result[64]!=add_result[63])state<=H229;else state<=H89; end
H89:begin 
state<=H91; end
H90:begin covariance<=0;
state<=H91; end
H91:begin 
state<=H92; end
H92:begin 
if(col==3)state<=H94;else state<=H93; end
H93:begin col<=col+1'b1;
state<=H70; end
H94:begin 
if(row==3)state<=H96;else state<=H95; end
H95:begin row<=row+1'b1;col<=row+1'b1;
state<=H70; end
H96:begin trace_value<=0;inner<=0;
state<=H97; end
H97:begin 
state<=H98; end
H98:begin term<=tensor_qa;
state<=H99; end
H99:begin trace_value<=add_result[63:0];
if(add_result[64]!=add_result[63])state<=H229;else state<=H100; end
H100:begin 
if(inner==3)state<=H102;else state<=H101; end
H101:begin inner<=inner+1'b1;
state<=H97; end
H102:begin 
state<=H103; end
H103:begin if(math_response)begin scale_value<=math_value;end
if(math_response)begin if(math_error)state<=H229;else state<=H104;end end
H104:begin if(scale_value<64'sd268435456)scale_value<=64'sd268435456;
state<=H105; end
H105:begin 
state<=H106; end
H106:begin if(math_response)begin root_scale<=math_value;end
if(math_response)begin if(math_error)state<=H229;else state<=H107;end end
H107:begin matrix_index<=0;
state<=H108; end
H108:begin 
state<=H109; end
H109:begin term<=tensor_qa;
state<=H110; end
H110:begin 
state<=H111; end
H111:begin if(math_response)begin term<=math_value;end
if(math_response)begin if(math_error)state<=H229;else state<=H112;end end
H112:begin 
if(matrix_index%5!=0)state<=H114;else state<=H113; end
H113:begin term<=add_result[63:0];
if(add_result[64]!=add_result[63])state<=H229;else state<=H114; end
H114:begin 
state<=H115; end
H115:begin 
if(matrix_index==15)state<=H117;else state<=H116; end
H116:begin matrix_index<=matrix_index+1'b1;
state<=H108; end
H117:begin owner<=4;eigen_keep_vectors<=1;
state<=H118; end
H118:begin 
state<=H119; end
H119:begin 
if(eigen_done)begin if(eigen_fault)state<=H229;else state<=H120;end end
H120:begin owner<=0;
state<=H121; end
H121:begin 
state<=H122; end
H122:begin if(math_response)begin eigen_max<=math_value;end
if(math_response)begin if(math_error)state<=H229;else state<=H123;end end
H123:begin inner<=0;
state<=H124; end
H124:begin 
state<=H125; end
H125:begin term<=tensor_qa;
state<=H126; end
H126:begin if(term>eigen_max)eigen_max<=term;
state<=H127; end
H127:begin 
if(inner==3)state<=H129;else state<=H128; end
H128:begin inner<=inner+1'b1;
state<=H124; end
H129:begin 
state<=H130; end
H130:begin if(math_response)begin cutoff<=math_value;end
if(math_response)begin if(math_error)state<=H229;else state<=H131;end end
H131:begin inner<=0;
state<=H132; end
H132:begin 
state<=H133; end
H133:begin term<=tensor_qa;
state<=H134; end
H134:begin if(term<cutoff)term<=cutoff;
state<=H135; end
H135:begin 
state<=H136; end
H136:begin if(math_response)begin term<=math_value;end
if(math_response)begin if(math_error)state<=H229;else state<=H137;end end
H137:begin 
state<=H138; end
H138:begin if(math_response)begin term<=math_value;end
if(math_response)begin if(math_error)state<=H229;else state<=H139;end end
H139:begin inverse[inner]<=term;
state<=H140; end
H140:begin 
if(inner==3)state<=H142;else state<=H141; end
H141:begin inner<=inner+1'b1;
state<=H132; end
H142:begin row<=0;col<=0;
state<=H143; end
H143:begin inner<=0;whiten_sum<=0;
state<=H144; end
H144:begin 
state<=H145; end
H145:begin 
state<=H146; end
H146:begin if(math_response)begin term<=math_value;end
if(math_response)begin if(math_error)state<=H229;else state<=H147;end end
H147:begin 
state<=H148; end
H148:begin if(math_response)begin term_scaled<=math_value;end
if(math_response)begin if(math_error)state<=H229;else state<=H149;end end
H149:begin whiten_sum<=add_result[63:0];
if(add_result[64]!=add_result[63])state<=H229;else state<=H150; end
H150:begin 
if(inner==3)state<=H152;else state<=H151; end
H151:begin inner<=inner+1'b1;
state<=H144; end
H152:begin 
state<=H153; end
H153:begin 
if(col==3)state<=H155;else state<=H154; end
H154:begin col<=col+1'b1;
state<=H143; end
H155:begin 
if(row==3)state<=H157;else state<=H156; end
H156:begin row<=row+1'b1;col<=row+1'b1;
state<=H143; end
H157:begin target<=0;
state<=H158; end
H158:begin row<=0;col<=0;
state<=H159; end
H159:begin 
if(!good_mask[row])state<=H175;else state<=H160; end
H160:begin covariance_sum<=0;covariance_lag<=local_covariance?7'd1:7'd0;
state<=H161; end
H161:begin owner<=2;vector_source_a<=`HW_XB+row_band;vector_source_b<=template_base;vector_periodic<=1;vector_length<=16'd250-{9'd0,covariance_lag};vector_denominator<=250;vector_lag<=covariance_lag;
state<=H162; end
H162:begin 
state<=H163; end
H163:begin 
if(vector_done)begin if(vector_fault)state<=H229;else state<=H164;end end
H164:begin owner<=0;covariance<=vector_value;
state<=H165; end
H165:begin 
if(!local_covariance)state<=H174;else state<=H166; end
H166:begin 
state<=H167; end
H167:begin lag_weight<=ram_qa;
state<=H168; end
H168:begin 
state<=H169; end
H169:begin if(math_response)begin weighted_covariance<=math_value;end
if(math_response)begin if(math_error)state<=H229;else state<=H170;end end
H170:begin covariance_sum<=add_result[63:0];
if(add_result[64]!=add_result[63])state<=H229;else state<=H171; end
H171:begin 
if(covariance_lag==11)state<=H173;else state<=H172; end
H172:begin covariance_lag<=covariance_lag+1'b1;
state<=H161; end
H173:begin covariance<=covariance_sum;
state<=H174; end
H174:begin 
state<=H176; end
H175:begin covariance<=0;
state<=H176; end
H176:begin 
state<=H177; end
H177:begin 
if(col==3)state<=H179;else state<=H178; end
H178:begin col<=col+1'b1;
state<=H159; end
H179:begin 
if(row==3)state<=H181;else state<=H180; end
H180:begin row<=row+1'b1;col<=0;
state<=H159; end
H181:begin matrix_index<=0;
state<=H182; end
H182:begin 
state<=H183; end
H183:begin term<=ram_qa;
state<=H184; end
H184:begin 
state<=H185; end
H185:begin 
if(matrix_index==15)state<=H187;else state<=H186; end
H186:begin matrix_index<=matrix_index+1'b1;
state<=H182; end
H187:begin owner<=3;matrix_pass<=2'd0;
state<=H188; end
H188:begin 
state<=H189; end
H189:begin 
if(matrix_done)begin if(matrix_fault)state<=H229;else state<=H190;end end
H190:begin owner<=0;
state<=H191; end
H191:begin matrix_index<=0;
state<=H192; end
H192:begin 
state<=H193; end
H193:begin term<=tensor_qa;
state<=H194; end
H194:begin 
state<=H195; end
H195:begin if(math_response)begin term<=math_value;end
if(math_response)begin if(math_error)state<=H229;else state<=H196;end end
H196:begin 
state<=H197; end
H197:begin 
if(matrix_index==15)state<=H199;else state<=H198; end
H198:begin matrix_index<=matrix_index+1'b1;
state<=H192; end
H199:begin owner<=3;matrix_pass<=2'd1;
state<=H200; end
H200:begin 
state<=H201; end
H201:begin 
if(matrix_done)begin if(matrix_fault)state<=H229;else state<=H202;end end
H202:begin owner<=0;
state<=H203; end
H203:begin owner<=3;matrix_pass<=2'd2;
state<=H204; end
H204:begin 
state<=H205; end
H205:begin 
if(matrix_done)begin if(matrix_fault)state<=H229;else state<=H206;end end
H206:begin owner<=0;
state<=H207; end
H207:begin owner<=4;eigen_keep_vectors<=0;
state<=H208; end
H208:begin 
state<=H209; end
H209:begin 
if(eigen_done)begin if(eigen_fault)state<=H229;else state<=H210;end end
H210:begin owner<=0;
state<=H211; end
H211:begin inner<=0;candidate_max<=0;
state<=H212; end
H212:begin 
state<=H213; end
H213:begin term<=tensor_qa;
state<=H214; end
H214:begin if(term>candidate_max)candidate_max<=term;
state<=H215; end
H215:begin 
if(inner==3)state<=H217;else state<=H216; end
H216:begin inner<=inner+1'b1;
state<=H212; end
H217:begin if(candidate_max>64'sd268435456)candidate_max<=64'sd268435456;
state<=H218; end
H218:begin 
state<=H219; end
H219:begin band_weight<=ram_qa;
state<=H220; end
H220:begin 
state<=H221; end
H221:begin if(math_response)begin weighted_score<=math_value;end
if(math_response)begin if(math_error)state<=H229;else state<=H222;end end
H222:begin scores[target]<=add_result[63:0];
if(add_result[64]!=add_result[63])state<=H229;else state<=H223; end
H223:begin 
if(target==4)state<=H225;else state<=H224; end
H224:begin target<=target+1'b1;
state<=H158; end
H225:begin 
if(band==4)state<=H227;else state<=H226; end
H226:begin band<=band+1'b1;
state<=H56; end
H227:begin score0<=scores[0];score1<=scores[1];score2<=scores[2];score3<=scores[3];score4<=scores[4];channel_mask<=good_mask;check_epoch<=frame_epoch;check_sequence<=frame_sequence;check_valid<=1;
state<=H0; end
H228:begin score0<=0;score1<=0;score2<=0;score3<=0;score4<=0;channel_mask<=good_mask;check_epoch<=frame_epoch;check_sequence<=frame_sequence;check_valid<=1;
state<=H0; end
H229:begin owner<=0;numeric_fault<=1;accepted_count<=0;hop_count<=0;initialized<=0;
state<=H228; end
default:state<=H229;
endcase
end
end
assign sample_ready=state==H0;
assign debug_phase=state;
endmodule
