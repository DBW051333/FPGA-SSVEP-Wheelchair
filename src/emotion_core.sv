// Compact fixed-point Conformer-style network with demonstration weights.
// Q8 weights/activations, saturating int16; int64 MAC; power-of-two LN/exp.
// 125Hz x8 -> 5 pooled convolution tokens x8 -> one attention block -> 3 logits.
// Sequential layers share a multiply-accumulate datapath.
module emotion_core #(
 parameter WEIGHTS="assets/emotion_demo_7bit.hex"
)(input wire clk,rst_n,enable,sample_valid,discontinuity,
 input wire [255:0] samples,
 output reg busy,result_valid,output reg [1:0] label,
 output reg signed [15:0] score0,score1,score2,
 output reg overrun);
 reg [5:0] state;reg [6:0] count;reg [2:0] c,t,o,p,job;
 reg [5:0] k,nshift;reg nbank;reg signed [31:0] nmean;
 reg [2:0] conv_ch,conv_tap;
 // Weight range is [-48,48]; a 7-bit signed ROM (emotion_demo_7bit.hex)
 // halves the storage vs. the original 16-bit words with bit-exact values.
 (* syn_romstyle="block_rom" *) reg signed [6:0] w[0:1023];initial $readmemh(WEIGHTS,w);
 reg signed [63:0] sums[0:7];
 // Small-index multipliers are rewritten as shifts to avoid DSP mapping.
 wire [6:0] raw_read_index=(t<<4)+(t<<3)+t+(p<<2)+p+conv_tap;
 wire signed [31:0] raw_read[0:7];
 genvar channel;
 generate for(channel=0;channel<8;channel=channel+1)begin:input_banks
  (* syn_ramstyle="block_ram" *) reg signed [31:0] memory[0:127];reg signed [31:0] read_value;
  always @(posedge clk)begin
   if(state==0&&sample_valid&&enable&&rst_n&&!discontinuity)
    memory[count[6:0]]<=samples[channel*32+:32];
   read_value<=memory[raw_read_index];
  end
  assign raw_read[channel]=read_value;
 end endgenerate
 reg signed [31:0] means[0:7];
 reg signed [15:0] tok[0:39],norm[0:39];
 reg signed [15:0] res[0:39],hidden[0:39],pooled[0:7],logits[0:2];
 reg signed [63:0] acc,pool_acc,variance;
 reg wide_start;reg signed [63:0] wide_num;reg [15:0] wide_den;
 wire wide_done;wire signed [63:0] wide_q;
 emotion_divider #(.WIDTH(64)) wide_divide(clk,rst_n,wide_start,wide_num,wide_den,wide_done,wide_q);
 function automatic signed [15:0] sat(input signed [63:0] v);
  begin if(v>32767)sat=32767;else if(v< -32768)sat=-32768;else sat=v[15:0];end
 endfunction
 function automatic integer scale_shift(input [63:0] v);
  begin
   // floor(log2(v)) / 2, i.e. the highest set bit position halved. A single
   // priority encoder replaces the original 63-wide magnitude comparison.
   scale_shift =
    (v[63]||v[62])?31:(v[61]||v[60])?30:(v[59]||v[58])?29:(v[57]||v[56])?28:
    (v[55]||v[54])?27:(v[53]||v[52])?26:(v[51]||v[50])?25:(v[49]||v[48])?24:
    (v[47]||v[46])?23:(v[45]||v[44])?22:(v[43]||v[42])?21:(v[41]||v[40])?20:
    (v[39]||v[38])?19:(v[37]||v[36])?18:(v[35]||v[34])?17:(v[33]||v[32])?16:
    (v[31]||v[30])?15:(v[29]||v[28])?14:(v[27]||v[26])?13:(v[25]||v[24])?12:
    (v[23]||v[22])?11:(v[21]||v[20])?10:(v[19]||v[18])?9:(v[17]||v[16])?8:
    (v[15]||v[14])?7:(v[13]||v[12])?6:(v[11]||v[10])?5:(v[9]||v[8])?4:
    (v[7]||v[6])?3:(v[5]||v[4])?2:(v[3]||v[2])?1:0;
  end
 endfunction
 function automatic integer base(input integer task_id);
  begin case(task_id)3:base=544;
   4:base=616;5:base=688;default:base=760;endcase end
 endfunction
 reg signed [15:0] operand;reg signed [31:0] product;
 reg signed [31:0] product_pipe;reg mac_conv;
 reg signed [63:0] total,value,centered;reg signed [15:0] activation;
 wire signed [17:0] norm_delta=$signed(nbank==0?tok[t*8+k]:res[t*8+k])-nmean;
 wire signed [35:0] norm_square=norm_delta*norm_delta;
 integer i;reg [9:0] wi;reg [5:0] idx;
 always @*begin
  operand=0;wi=0;centered=0;
  if(state==3||state==21||(state==25&&mac_conv))begin
   idx={3'd0,conv_ch};
   centered=($signed(raw_read[conv_ch])-$signed(means[conv_ch]))>>>7;
   operand=sat(centered);wi=(o<<5)+(o<<3)+k;
  end else begin
   idx=t*8+k;
   case(job)
    3,4:operand=norm[idx];
    5:operand=hidden[idx];default:operand=pooled[k];
   endcase
   wi=base(job)+(o<<3)+k;
  end
  product=$signed(operand)*$signed(w[wi]);
  total=acc+product_pipe;
  value=total>>>8;activation=sat(value);
 end
 always @(posedge clk)begin
  if(!rst_n||!enable||discontinuity)begin
   state<=0;count<=0;c<=0;t<=0;o<=0;k<=0;p<=0;job<=0;nbank<=0;
   acc<=0;pool_acc<=0;variance<=0;nmean<=0;nshift<=0;
   busy<=0;result_valid<=0;label<=0;score0<=0;score1<=0;score2<=0;overrun<=0;
   wide_start<=0;wide_num<=0;wide_den<=1;conv_ch<=0;conv_tap<=0;
   product_pipe<=0;mac_conv<=0;
   for(i=0;i<8;i=i+1)sums[i]<=0;
  end else begin
   result_valid<=0;overrun<=0;wide_start<=0;
   if(sample_valid&&state!=0)begin overrun<=1;end
   case(state)
    0:if(sample_valid)begin
     for(i=0;i<8;i=i+1)begin
      sums[i]<=sums[i]+$signed(samples[i*32+:32]);
     end
     if(count==124)begin count<=0;c<=0;busy<=1;state<=1;end else count<=count+1;
    end
    1:begin wide_num<=sums[c];wide_den<=125;wide_start<=1;state<=23;end
    23:if(wide_done)begin
     means[c]<=wide_q;sums[c]<=0;
     if(c==7)begin t<=0;o<=0;p<=0;k<=0;pool_acc<=0;state<=2;end else begin c<=c+1;state<=1;end
    end
    2:begin acc<=$signed(w[320+o])*256;k<=0;conv_ch<=0;conv_tap<=0;mac_conv<=1;state<=21;end
    21:state<=25;
    // Separate weight selection/multiplication from the 64-bit accumulation.
    // State 21 still provides the original synchronous raw-input read cycle.
    25:begin product_pipe<=product;state<=mac_conv?3:8;end
    3:begin
     if(k==39)begin
      if(p==4)begin
       wide_num<=pool_acc+(activation>0?activation:0);wide_den<=5;wide_start<=1;state<=22;
      end else begin pool_acc<=pool_acc+(activation>0?activation:0);p<=p+1;state<=2;end
     end else begin acc<=total;k<=k+1;
      if(conv_tap==4)begin conv_tap<=0;conv_ch<=conv_ch+1'b1;end else conv_tap<=conv_tap+1'b1;
      state<=21;end
    end
    22:if(wide_done)begin
     tok[t*8+o]<=wide_q;pool_acc<=0;p<=0;
     if(o==7)begin o<=0;if(t==4)begin t<=0;k<=0;acc<=0;nbank<=0;state<=4;end
      else begin t<=t+1;state<=2;end end
     else begin o<=o+1;state<=2;end
    end
    // Layer normalization with power-of-two standard deviation approximation.
    4:begin
     if(k==7)begin nmean<=(acc+(nbank==0?tok[t*8+k]:res[t*8+k]))>>>3;
      k<=0;variance<=0;state<=5;end
     else begin acc<=acc+(nbank==0?tok[t*8+k]:res[t*8+k]);k<=k+1;end
    end
    5:begin
     if(k==7)begin
      nshift<=scale_shift((variance+norm_square)>>>3);
      k<=0;state<=6;
     end else begin
      variance<=variance+norm_square;k<=k+1;
     end
    end
    6:begin
     norm[t*8+k]<=sat((($signed(nbank==0?tok[t*8+k]:res[t*8+k])-nmean)*64'sd256)>>>nshift);
     if(k==7)begin
      k<=0;acc<=0;
      if(t==4)begin t<=0;o<=0;job<=nbank==0?3:4;state<=7;end
      else begin t<=t+1;state<=4;end
     end else k<=k+1;
    end
    7:begin acc<=$signed(w[base(job)+(job==6?24:64)+o])*256;k<=0;mac_conv<=0;state<=25;end
    8:begin
     if(k==7)begin
      case(job)
       3:res[t*8+o]<=sat($signed(tok[t*8+o])+$signed(activation));
       4:hidden[t*8+o]<=activation>0?activation:0;
       5:tok[t*8+o]<=sat($signed(res[t*8+o])+$signed(activation));
       6:logits[o]<=activation;
      endcase
      if(o==(job==6?2:7))begin
       o<=0;
       if(job==6)state<=20;
       else if(t==4)begin
        t<=0;k<=0;acc<=0;
        case(job)
         3:begin nbank<=1;state<=4;end
         4:begin job<=5;state<=7;end
         5:begin state<=18;c<=0;end
        endcase
       end else begin t<=t+1;state<=7;end
      end else begin o<=o+1;state<=7;end
     end else begin acc<=total;k<=k+1;state<=25;end
    end
    18:begin
     if(t==4)begin wide_num<=acc+$signed(tok[t*8+c]);wide_den<=5;wide_start<=1;state<=24;end
     else begin acc<=acc+$signed(tok[t*8+c]);t<=t+1;end
    end
    24:if(wide_done)begin pooled[c]<=wide_q;acc<=0;t<=0;
     if(c==7)begin o<=0;job<=6;state<=7;end else begin c<=c+1;state<=18;end
    end
    20:begin
     score0<=logits[0];score1<=logits[1];score2<=logits[2];
     label<=(logits[0]>=logits[1]&&logits[0]>=logits[2])?0:(logits[1]>=logits[2]?1:2);
     result_valid<=1;busy<=0;state<=0;
    end
    default:begin state<=0;busy<=0;end
   endcase
   // A sample arriving while inference is busy breaks the contiguous window.
   // Abort rather than silently skipping it and reporting a misleading result.
   if(sample_valid&&state!=0)begin
    state<=0;count<=0;busy<=0;result_valid<=0;
    for(i=0;i<8;i=i+1)sums[i]<=0;
   end
  end
 end
endmodule

