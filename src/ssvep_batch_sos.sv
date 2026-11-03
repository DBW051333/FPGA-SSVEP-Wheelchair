`include "ssvep_hardware_layout.vh"
// Four independent EEG channels occupy one deterministic 20-product schedule.
// No opcodes, registers addressed by instructions, or programmable sequencer.
module ssvep_batch_sos(
 input wire clk,rst_n,start,window_mode,skip_history,
 input wire [2:0] band,input wire [3:0] initialize,
 input wire [255:0] input_samples,
 output logic done,fault,output wire [255:0] filtered,
 output logic [13:0] aa,ab,output logic we,output logic signed [63:0] wd,
 input wire signed [63:0] qa,qb,
 output logic product_valid,output logic signed [63:0] product_a,product_b,
 input wire product_done,product_overflow,input wire signed [63:0] product_value);
 typedef enum logic [4:0] {IDLE,COEF_REQ,COEF_GET,INPUT_REQ,INPUT_GET,
  STATE_REQ,STATE_GET,SEED_ISSUE,SEED_DRAIN,RUN_ISSUE,RUN_DRAIN,
  SAVE_STATE,SAVE_OUTPUT,ADVANCE_SAMPLE,FINISH} state_t;
 state_t state;
 logic mode,history_skip,pair;
 logic [3:0] need_initialize;
 logic [2:0] current_band;
 logic [5:0] coef_index,coef_count;
 logic [3:0] section,section_count;
 logic [8:0] sample_index,sample_count,discard_count;
 logic [1:0] channel;
 logic [4:0] issued,received;
 logic [3:0] store_index;
 logic signed [31:0] coefficient[0:44];
 logic signed [63:0] x[0:3],y[0:3],seed[0:3];
 logic [511:0] window_state0,window_state1,window_state2,window_state3;
 wire [511:0] selected_window_state=section[1:0]==0?window_state0:
     section[1:0]==1?window_state1:section[1:0]==2?window_state2:window_state3;
 logic signed [63:0] z1[0:3],z2[0:3],m1[0:3],m2[0:3];
 wire [2:0] product_phase=issued[4:2],return_phase=received[4:2];
 wire [1:0] issue_channel=issued[1:0],return_channel=received[1:0];
 wire [6:0] coef_slot={section,2'b00}+{3'd0,section}+{4'd0,product_phase};
 wire [13:0] coefficient_base=mode?`HW_BANKCOEF+14'(current_band*20):`HW_PRE;
 wire [13:0] initial_base=mode?`HW_BANKZI+14'(current_band*8):`HW_PREZI;
 wire [13:0] state_base=mode?14'd130:`HW_PSTATE;
 wire [13:0] state_stride=mode?14'd8:14'd18;
 wire [13:0] source_base=`HW_X+(history_skip?14'd62:14'd0);
 wire initialize_channel=mode?(sample_index==0):need_initialize[channel];
 wire [64:0] y_wide={product_value[63],product_value}+{z1[return_channel][63],z1[return_channel]};
 wire [64:0] delta_wide={m1[return_channel][63],m1[return_channel]}-{product_value[63],product_value};
 wire [64:0] z1_wide={delta_wide[63],delta_wide[63:0]}+{z2[return_channel][63],z2[return_channel]};
 wire [64:0] z2_wide={m2[return_channel][63],m2[return_channel]}-{product_value[63],product_value};
 assign filtered={y[0],y[1],y[2],y[3]};
 always_comb begin
  aa=0;ab=0;we=0;wd=0;product_valid=0;product_a=0;product_b=0;
  case(state)
   COEF_REQ,COEF_GET:aa=coefficient_base+{8'd0,coef_index};
   INPUT_REQ,INPUT_GET:begin
    aa=source_base+14'((pair?2:0)*312)+{5'd0,sample_index};
    ab=source_base+14'((pair?3:1)*312)+{5'd0,sample_index};
   end
   STATE_REQ,STATE_GET:begin
    aa=initialize_channel?initial_base+14'(section*2):state_base+14'(channel*state_stride)+14'(section*2);
    ab=aa+14'd1;
   end
   SEED_ISSUE:begin
    product_valid=1;
    product_a=issued[0]?z2[issued[2:1]]:z1[issued[2:1]];
    product_b=(mode||need_initialize[issued[2:1]])?seed[issued[2:1]]:64'sd268435456;
   end
   RUN_ISSUE:begin
    product_valid=1;
    product_a={{32{coefficient[coef_slot][31]}},coefficient[coef_slot]};
    product_b=product_phase<3?x[issue_channel]:y[issue_channel];
   end
   SAVE_STATE:begin
    aa=state_base+14'(store_index[2:1]*state_stride)+14'(section*2)+{13'd0,store_index[0]};
    we=(!mode || sample_index+1'b1==sample_count);wd=store_index[0]?z2[store_index[2:1]]:z1[store_index[2:1]];
   end
   SAVE_OUTPUT:begin
    aa=`HW_XB+14'(channel*250)+{5'd0,sample_index}-{5'd0,discard_count};we=1;wd=y[channel];
   end
   default:;
  endcase
 end
 integer i;
 always_ff @(posedge clk)begin
  if(!rst_n)begin
   state<=IDLE;done<=0;fault<=0;mode<=0;history_skip<=0;current_band<=0;need_initialize<=0;
   issued<=0;received<=0;coef_index<=0;coef_count<=0;section<=0;section_count<=0;
   sample_index<=0;sample_count<=0;discard_count<=0;channel<=0;pair<=0;store_index<=0;
  end else begin
   done<=0;
   case(state)
    IDLE:if(start)begin
     fault<=0;mode<=window_mode;history_skip<=skip_history;current_band<=band;need_initialize<=initialize;
     coef_index<=0;coef_count<=window_mode?20:45;section_count<=window_mode?4:9;
     sample_index<=0;sample_count<=window_mode?(skip_history?250:312):1;
     discard_count<=window_mode?(skip_history?0:62):0;section<=0;channel<=0;pair<=0;
     for(i=0;i<4;i=i+1)begin x[i]<=$signed(input_samples[(3-i)*64+:64]);seed[i]<=$signed(input_samples[(3-i)*64+:64]);end
     state<=COEF_REQ;
    end
    COEF_REQ:state<=COEF_GET;
    COEF_GET:begin
     coefficient[coef_index]<=qa[31:0];
     if(qa!=$signed({{32{qa[31]}},qa[31:0]}))begin fault<=1;state<=FINISH;end
     else if(coef_index+1'b1==coef_count)begin channel<=0;state<=mode?INPUT_REQ:STATE_REQ;end
     else begin coef_index<=coef_index+1'b1;state<=COEF_REQ;end
    end
    INPUT_REQ:state<=INPUT_GET;
    INPUT_GET:begin
     x[pair?2:0]<=qa;x[pair?3:1]<=qb;
     if(sample_index==0)begin seed[pair?2:0]<=qa;seed[pair?3:1]<=qb;end
     if(pair)begin pair<=0;section<=0;channel<=0;state<=STATE_REQ;end
     else begin pair<=1;state<=INPUT_REQ;end
    end
    STATE_REQ:begin
     if(mode&&sample_index!=0)begin
      for(i=0;i<4;i=i+1)begin
       z1[i]<=selected_window_state[i*128+:64];
       z2[i]<=selected_window_state[i*128+64+:64];
      end
      issued<=0;received<=0;state<=RUN_ISSUE;
     end else state<=STATE_GET;
    end
    STATE_GET:begin
     z1[channel]<=qa;z2[channel]<=qb;
     if(channel==3)begin
      channel<=0;issued<=0;received<=0;
      state<=((mode&&sample_index==0)||(!mode&&need_initialize!=0))?SEED_ISSUE:RUN_ISSUE;
     end else begin channel<=channel+1'b1;state<=STATE_REQ;end
    end
    SEED_ISSUE:begin issued<=issued+1'b1;if(issued==7)state<=SEED_DRAIN;end
    SEED_DRAIN:;
    RUN_ISSUE:begin issued<=issued+1'b1;if(issued==19)state<=RUN_DRAIN;end
    RUN_DRAIN:;
    SAVE_STATE:begin
     if(mode&&sample_index+1'b1!=sample_count || store_index==7)begin
      if(mode)case(section[1:0])
      2'd0:for(i=0;i<4;i=i+1)begin
       window_state0[i*128+:64]<=z1[i];
       window_state0[i*128+64+:64]<=z2[i];
      end
      2'd1:for(i=0;i<4;i=i+1)begin
       window_state1[i*128+:64]<=z1[i];
       window_state1[i*128+64+:64]<=z2[i];
      end
      2'd2:for(i=0;i<4;i=i+1)begin
       window_state2[i*128+:64]<=z1[i];
       window_state2[i*128+64+:64]<=z2[i];
      end
      2'd3:for(i=0;i<4;i=i+1)begin
       window_state3[i*128+:64]<=z1[i];
       window_state3[i*128+64+:64]<=z2[i];
      end
      endcase
      store_index<=0;
      if(section+1'b1==section_count)begin
       channel<=0;
       if(!mode)state<=FINISH;
       else state<=sample_index>=discard_count?SAVE_OUTPUT:ADVANCE_SAMPLE;
      end else begin
       for(i=0;i<4;i=i+1)x[i]<=y[i];
       section<=section+1'b1;channel<=0;state<=STATE_REQ;
      end
     end else store_index<=store_index+1'b1;
    end
    SAVE_OUTPUT:if(channel==3)begin channel<=0;state<=ADVANCE_SAMPLE;end else channel<=channel+1'b1;
    ADVANCE_SAMPLE:begin
     if(sample_index+1'b1==sample_count)state<=FINISH;
     else begin sample_index<=sample_index+1'b1;section<=0;pair<=0;state<=INPUT_REQ;end
    end
    FINISH:begin done<=1;state<=IDLE;end
    default:begin fault<=1;state<=FINISH;end
   endcase
   if(product_done&&(state==SEED_ISSUE||state==SEED_DRAIN||state==RUN_ISSUE||state==RUN_DRAIN))begin
    received<=received+1'b1;
    if(state==SEED_ISSUE||state==SEED_DRAIN)begin
     if(received[0])z2[received[2:1]]<=product_value;else z1[received[2:1]]<=product_value;
     if(received==7)begin issued<=0;received<=0;state<=RUN_ISSUE;end
    end else begin
     case(return_phase)
      0:begin y[return_channel]<=y_wide[63:0];if(y_wide[64]!=y_wide[63])begin fault<=1;state<=FINISH;end end
      1:m1[return_channel]<=product_value;
      2:m2[return_channel]<=product_value;
      3:begin z1[return_channel]<=z1_wide[63:0];if(delta_wide[64]!=delta_wide[63]||z1_wide[64]!=z1_wide[63])begin fault<=1;state<=FINISH;end end
      4:begin z2[return_channel]<=z2_wide[63:0];if(z2_wide[64]!=z2_wide[63])begin fault<=1;state<=FINISH;end end
      default:begin fault<=1;state<=FINISH;end
     endcase
     if(received==19)begin store_index<=0;state<=SAVE_STATE;end
    end
    if(product_overflow)begin fault<=1;state<=FINISH;end
   end
  end
 end
endmodule
