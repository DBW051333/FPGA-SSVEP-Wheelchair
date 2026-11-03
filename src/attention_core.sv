// Four-channel SIMD rectangular DFT. One coefficient broadcast per lane issue.
// Exact original Q8/Q14 contract; 81 contributing bins; power only at window end.
module attention_core(input wire clk,rst_n,sample_valid,
 input wire signed [31:0] sample0,sample1,sample2,sample3,
 output wire ready,output reg [6:0] score,output reg valid,updated,
 output reg [2:0] good_channels,output reg fault);
 localparam integer BINS=81;
 (* syn_romstyle="block_rom" *) reg signed [15:0] sine[0:499];
 initial $readmemh("assets/sine.hex",sine);
 wire [8:0] phase_read;
 reg signed [31:0] samples[0:3],lo[0:3],hi[0:3];
 reg signed [39:0] sample_sum[0:3]; reg [63:0] sample_square_sum[0:3];
 reg signed [31:0] channel_mean[0:3]; reg [1:0] mean_channel;
 reg mean_start; reg signed [39:0] mean_num; wire mean_done; wire signed [39:0] mean_q;
 emotion_divider #(.WIDTH(40)) mean_divide(clk,rst_n,mean_start,mean_num,16'd500,mean_done,mean_q);
 (* syn_ramstyle="block_ram" *) reg signed [23:0] cosine_sum[0:BINS-1],sine_sum[0:BINS-1];
 reg signed [23:0] old_cosine_sum,old_sine_sum;
 wire signed [24:0] full_cosine_sum=$signed(old_cosine_sum)+$signed(cos_q);
 wire signed [24:0] full_sine_sum=$signed(old_sine_sum)+$signed(sin_q);
 reg signed [55:0] correction_r[0:3],correction_i[0:3];
 reg [79:0] n_squares,sum_squared,variance_n2;
 reg [1:0] square_channel;
 reg signed [39:0] square_operand;
 wire signed [79:0] shared_square=square_operand*square_operand;
 reg [3:0] clipped;
 reg [63:0] alpha[0:3],beta[0:3];
 reg [63:0] total_a,total_b,smooth_a,smooth_b;
 reg have_power;reg [8:0] n,clear_addr;reg [6:0] bin;reg [1:0] channel;
 reg [4:0] state;
 reg signed [55:0] old_r[0:3],old_i[0:3];
 reg signed [55:0] new_r[0:3],new_i[0:3];
 reg signed [47:0] prod_r[0:3],prod_i[0:3];
 reg signed [15:0] sin_q,cos_q;
 reg signed [31:0] scaled_r[0:3],scaled_i[0:3];
 always @* begin
  square_operand=0;
  case(state)
   6:square_operand={{8{scaled_r[channel][31]}},scaled_r[channel]};
   20:square_operand={{8{scaled_i[channel][31]}},scaled_i[channel]};
   8:square_operand=sample_sum[channel];
   18:square_operand={{8{samples[square_channel][31]}},samples[square_channel]};
   default:;
  endcase
 end
 reg signed [24:0] coefficient;
 always @* begin
  case(state)
   3:coefficient={{9{cos_q[15]}},cos_q};
   21:coefficient={{9{sin_q[15]}},sin_q};
   4:coefficient=n==499?full_cosine_sum:25'sd0;
   22:coefficient=full_sine_sum;
   default:coefficient=0;
  endcase
 end
 wire signed [56:0] lane_product[0:3];
 genvar g;
 generate for(g=0;g<4;g=g+1)begin:channel_lanes
  wire signed [31:0] operand=(state==4||state==22)?channel_mean[g]:samples[g];
  assign lane_product[g]=operand*coefficient;
 end endgenerate
 // Four SIMD contexts share a 112-bit true-dual-port memory. Independent ports
 // preload two channels per clock, hidden under the twiddle/product pipeline.
 wire [111:0] context_qa,context_qb;
 reg [8:0] context_aa,context_ab;
 reg [111:0] context_da,context_db;
 reg context_wea,context_web,context_write_pending;
 always @*begin
  context_aa={2'd0,bin};context_ab=9'd81+{2'd0,bin};
  context_da=0;context_db=0;context_wea=0;context_web=0;
  if(state==0)begin
   context_aa=clear_addr<<1;context_ab=(clear_addr<<1)+9'd1;
   context_wea=1;context_web=1;
  end else if(state==5)begin
   context_wea=1;context_web=1;
   context_da=n==499?112'd0:{new_r[0],new_i[0]};
   context_db=n==499?112'd0:{new_r[1],new_i[1]};
  end else if(context_write_pending)begin
   context_aa=9'd162+{2'd0,bin};context_ab=9'd243+{2'd0,bin};
   context_wea=1;context_web=1;
   context_da=n==499?112'd0:{new_r[2],new_i[2]};
   context_db=n==499?112'd0:{new_r[3],new_i[3]};
  end else if(state==2)begin
   context_aa=9'd162+{2'd0,bin};context_ab=9'd243+{2'd0,bin};
  end
 end
 attention_context_ram context_memory(clk,context_wea&&rst_n,context_web&&rst_n,
  context_aa,context_ab,context_da,context_db,context_qa,context_qb);
 always @(posedge clk)begin
  if(!rst_n)context_write_pending<=0;
  else begin
   context_write_pending<=state==5;
   if(state==2)begin
    old_r[0]<=context_qa[111:56];old_i[0]<=context_qa[55:0];
    old_r[1]<=context_qb[111:56];old_i[1]<=context_qb[55:0];
   end
   if(state==3)begin
    old_r[2]<=context_qa[111:56];old_i[2]<=context_qa[55:0];
    old_r[3]<=context_qb[111:56];old_i[3]<=context_qb[55:0];
   end
  end
 end
 reg [63:0] square_r,square_i;
 reg [71:0] numerator,denominator,quotient,remainder;
 reg [6:0] div_bit,target;
 reg [8:0] cos_addr;
 // Compact indices skip 12.25..12.75 Hz and the excluded 24.5..25.5 Hz band.
 wire [7:0] freq_bin=bin<=16?{1'b0,bin}+8'd32:bin<=62?{1'b0,bin}+8'd35:{1'b0,bin}+8'd40;
 wire alpha_bin=bin<=16;
 wire beta_bin=bin>=17;
 wire [9:0] phase_next={1'b0,phase_read}+freq_bin;
 wire phase_clear=state==0&&clear_addr<BINS;
 wire phase_write=rst_n&&(phase_clear||state==5);
 wire [8:0] phase_address=phase_clear?clear_addr:{2'b0,bin};
 wire [8:0] phase_value=phase_clear?9'd0:phase_next>=500?phase_next-500:phase_next;
 attention_phase_ram phase_memory(clk,phase_write,phase_address,phase_value,phase_read);
 wire signed [32:0] peak_to_peak=$signed({hi[channel][31],hi[channel]})-$signed({lo[channel][31],lo[channel]});
 wire channel_ok=!clipped[channel]&&variance_n2>=80'd40960000&&
                 variance_n2<80'd409600000000000000&&peak_to_peak<33'sd5120000;
 wire [72:0] trial_rem={remainder,numerator[71]};
 assign ready=state==1;
 integer k;
 always @(posedge clk)begin
  if(!rst_n)begin
   state<=0;square_channel<=0;clear_addr<=0;bin<=0;channel<=0;n<=0;score<=0;valid<=0;updated<=0;
   good_channels<=0;fault<=0;clipped<=0;have_power<=0;smooth_a<=0;smooth_b<=0;
   total_a<=0;total_b<=0;n_squares<=0;sum_squared<=0;variance_n2<=0;
   mean_start<=0;mean_num<=0;mean_channel<=0;old_cosine_sum<=0;old_sine_sum<=0;
   for(k=0;k<4;k=k+1)begin
    lo[k]<=32'sh7fffffff;hi[k]<=-32'sh7fffffff;alpha[k]<=0;beta[k]<=0;samples[k]<=0;
    sample_sum[k]<=0;sample_square_sum[k]<=0;channel_mean[k]<=0;
    correction_r[k]<=0;correction_i[k]<=0;
   end
  end else begin
   updated<=0;mean_start<=0;
   if(sample_valid&&!ready)fault<=1;
   case(state)
    0:begin
     if(clear_addr<BINS)begin cosine_sum[clear_addr]<=0;sine_sum[clear_addr]<=0;end
     if(clear_addr==161)state<=1;else clear_addr<=clear_addr+1'b1;
    end
    1:if(sample_valid)begin
     samples[0]<=sample0;samples[1]<=sample1;samples[2]<=sample2;samples[3]<=sample3;
     sample_sum[0]<=sample_sum[0]+sample0;sample_sum[1]<=sample_sum[1]+sample1;
     sample_sum[2]<=sample_sum[2]+sample2;sample_sum[3]<=sample_sum[3]+sample3;
     if(sample0>=38400000||sample0<= -38400000)clipped[0]<=1;
     if(sample1>=38400000||sample1<= -38400000)clipped[1]<=1;
     if(sample2>=38400000||sample2<= -38400000)clipped[2]<=1;
     if(sample3>=38400000||sample3<= -38400000)clipped[3]<=1;
     if(sample0<lo[0])lo[0]<=sample0;if(sample0>hi[0])hi[0]<=sample0;
     if(sample1<lo[1])lo[1]<=sample1;if(sample1>hi[1])hi[1]<=sample1;
     if(sample2<lo[2])lo[2]<=sample2;if(sample2>hi[2])hi[2]<=sample2;
     if(sample3<lo[3])lo[3]<=sample3;if(sample3>hi[3])hi[3]<=sample3;
     bin<=0;channel<=0;square_channel<=0;state<=18;
    end
    18:begin
     sample_square_sum[square_channel]<=sample_square_sum[square_channel]+shared_square[63:0];
     if(square_channel==3)begin
      if(n==499)begin mean_channel<=0;state<=16;end else state<=19;
     end else square_channel<=square_channel+1'b1;
    end
    16:begin mean_num<=sample_sum[mean_channel];mean_start<=1;state<=17;end
    17:if(mean_done)begin
     channel_mean[mean_channel]<=mean_q;
     if(mean_channel==3)state<=19;else begin mean_channel<=mean_channel+1'b1;state<=16;end
    end
    19:state<=2;
    2:begin
     sin_q<=sine[phase_read];old_cosine_sum<=cosine_sum[bin];old_sine_sum<=sine_sum[bin];
     cos_addr=phase_read>=375?phase_read-375:phase_read+125;
     cos_q<=sine[cos_addr];state<=3;
    end
    3:begin for(k=0;k<4;k=k+1)prod_r[k]<=lane_product[k][47:0];state<=21;end
    21:begin for(k=0;k<4;k=k+1)prod_i[k]<=lane_product[k][47:0];state<=4;end
    4:begin
     for(k=0;k<4;k=k+1)begin
      new_r[k]<=old_r[k]+prod_r[k];new_i[k]<=old_i[k]+prod_i[k];
      correction_r[k]<=n==499?lane_product[k][55:0]:56'sd0;
     end
     state<=n==499?22:5;
    end
    22:begin for(k=0;k<4;k=k+1)correction_i[k]<=lane_product[k][55:0];state<=5;end
    5:begin
     for(k=0;k<4;k=k+1)begin
      scaled_r[k]<=($signed(new_r[k])-$signed(correction_r[k]))>>>20;
      scaled_i[k]<=($signed(new_i[k])-$signed(correction_i[k]))>>>20;
     end
     cosine_sum[bin]<=n==499?24'sd0:full_cosine_sum;
     sine_sum[bin]<=n==499?24'sd0:full_sine_sum;
     channel<=0;state<=n==499?6:7;
    end
    6:begin square_r<=shared_square[63:0];state<=20;end
    20:begin square_i<=shared_square[63:0];state<=7;end
    7:begin
     if(n==499)begin
      if(alpha_bin)alpha[channel]<=alpha[channel]+square_r+square_i;
      if(beta_bin)beta[channel]<=beta[channel]+square_r+square_i;
     end
     if(n==499&&channel!=3)begin channel<=channel+1'b1;state<=6;end
     else if(bin==BINS-1)begin
      bin<=0;channel<=0;
      if(n==499)begin total_a<=0;total_b<=0;good_channels<=0;state<=8;end
      else begin n<=n+1'b1;state<=1;end
     end else begin bin<=bin+1'b1;state<=19;end
    end
    8:begin
     // x*500=(x<<9)-(x<<4)+(x<<2), retaining 80-bit modulo semantics.
     n_squares<=({16'd0,sample_square_sum[channel]}<<9)-
                ({16'd0,sample_square_sum[channel]}<<4)+
                ({16'd0,sample_square_sum[channel]}<<2);
     sum_squared<=shared_square;state<=14;end
    14:begin variance_n2<=n_squares-sum_squared;state<=15;end
    15:begin
     if(channel_ok)begin total_a<=total_a+alpha[channel];total_b<=total_b+beta[channel];good_channels<=good_channels+1'b1;end
     alpha[channel]<=0;beta[channel]<=0;lo[channel]<=32'sh7fffffff;hi[channel]<=-32'sh7fffffff;
     sample_sum[channel]<=0;sample_square_sum[channel]<=0;
     if(channel==3)begin state<=9;clipped<=0;n<=0;end else begin channel<=channel+1'b1;state<=8;end
    end
    9:begin
     if(good_channels>=2&&total_a>4)begin
      smooth_a<=have_power?total_a-(total_a>>4)+(smooth_a>>4):total_a;
      smooth_b<=have_power?total_b-(total_b>>4)+(smooth_b>>4):total_b;
      have_power<=1;state<=10;
     end else begin valid<=0;state<=1;end
    end
    10:begin
     if({1'b0,smooth_b,1'b0}<={2'b0,smooth_a})begin target<=0;state<=13;end
     else if({1'b0,smooth_b}>={smooth_a,1'b0})begin target<=100;state<=13;end
     else begin
      numerator<=((({8'd0,smooth_b}<<1)-{8'd0,smooth_a})<<6)+
                 ((({8'd0,smooth_b}<<1)-{8'd0,smooth_a})<<5)+
                 ((({8'd0,smooth_b}<<1)-{8'd0,smooth_a})<<2);
      denominator<=({8'd0,smooth_a}<<1)+{8'd0,smooth_a};
      quotient<=0;remainder<=0;div_bit<=71;state<=11;
     end
    end
    11:begin
     numerator<=numerator<<1;
     if(trial_rem>={1'b0,denominator})begin remainder<=trial_rem-denominator;quotient<={quotient[70:0],1'b1};end
     else begin remainder<=trial_rem;quotient<={quotient[70:0],1'b0};end
     if(div_bit==0)state<=12;else div_bit<=div_bit-1'b1;
    end
    12:begin target<=quotient>100?100:quotient[6:0];state<=13;end
    13:begin
     score<=valid?((score+{2'd0,target,1'b0}+{3'd0,target}+2)>>2):target;
     valid<=1;updated<=1;state<=1;end
    default:state<=0;
   endcase
  end
 end
endmodule

// Write-through single-port synchronous RAM, matching the supported Gowin template.
// The first 89 entries are initialized by the core's existing clear sequence.
module attention_phase_ram(input wire clk,we,input wire [8:0] address,
 input wire [8:0] data,output wire [8:0] q);
 wire [15:0] read_word;
 DPB #(.READ_MODE0(1'b0),.READ_MODE1(1'b0),.WRITE_MODE0(2'b01),
  .WRITE_MODE1(2'b00),.BIT_WIDTH_0(16),.BIT_WIDTH_1(16)) storage(
  .CLKA(clk),.CEA(1'b1),.OCEA(1'b1),.RESETA(1'b0),.WREA(we),
  .ADA({1'b0,address,2'b0,2'b11}),.DIA({7'd0,data}),.DOA(read_word),.BLKSELA(3'd0),
  .CLKB(clk),.CEB(1'b0),.OCEB(1'b0),.RESETB(1'b0),.WREB(1'b0),
  .ADB(14'd0),.DIB(16'd0),.DOB(),.BLKSELB(3'd0));
 assign q=read_word[8:0];
endmodule

// Seven physical DPBs, both ports shared by all four channel contexts.
// 324 logical 112-bit words retain exact real/imaginary 56-bit accumulators.
module attention_context_ram(input wire clk,wea,web,
 input wire [8:0] aa,ab,input wire [111:0] da,db,output wire [111:0] qa,qb);
 genvar k;
 generate for(k=0;k<7;k=k+1)begin:bit_slices
  DPB #(.READ_MODE0(1'b0),.READ_MODE1(1'b0),.WRITE_MODE0(2'b01),
        .WRITE_MODE1(2'b01),.BIT_WIDTH_0(16),.BIT_WIDTH_1(16)) memory(
   .CLKA(clk),.CEA(1'b1),.OCEA(1'b1),.RESETA(1'b0),.WREA(wea),
   .ADA({1'b0,aa,4'b0011}),.DIA(da[k*16+:16]),.DOA(qa[k*16+:16]),.BLKSELA(3'd0),
   .CLKB(clk),.CEB(1'b1),.OCEB(1'b1),.RESETB(1'b0),.WREB(web),
   .ADB({1'b0,ab,4'b0011}),.DIB(db[k*16+:16]),.DOB(qb[k*16+:16]),.BLKSELB(3'd0));
 end endgenerate
endmodule
