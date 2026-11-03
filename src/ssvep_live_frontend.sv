// Receiver is a 3.3 V TTL UART.
module ssvep_live_frontend #(parameter integer CLOCK_HZ=50000000,BAUD=115200,AUTO_MODE=0,COOLDOWN_CYCLES=CLOCK_HZ,RETRY_CYCLES=CLOCK_HZ*3,CONTINUOUS_MODE=0,SAME_TARGET_RETRIGGER=0)(
 input logic clk,rst_n,start_press,stop_press,receiver_rx,
 input wire [1:0] ui_page,ui_session_page,output wire [2:0] ui_state,
 output wire receiver_tx,output wire diagnostic_tx,output logic [2:0] display_code,
 input wire page_restart,output wire round_start,
 output wire stream_on,signal_fresh,fault,
 output logic command_valid,output wire [2:0] command_code,
 output wire eeg_byte_valid,eeg_byte_error,output wire [7:0] eeg_byte_data);
 localparam integer BOOT_CYCLES=CLOCK_HZ/2,COMMAND_GAP=CLOCK_HZ/5,REPLY_TIMEOUT=CLOCK_HZ*10;
 logic startup_fault;logic [1:0] reply_dollars;
 logic [3:0] state;logic [31:0] wait_count,fresh_count;logic running,core_start;
 // AUTO_MODE arms at power-up and reinitializes only after receiver faults.
 // Each completed/18-second timed-out round restarts after the action interval.
 logic trial_armed,trial_running,trial_done;
 logic target_latched;logic [2:0] latched_target;
 logic round_reset;logic [31:0] cooldown,retry_count;
 assign round_start=core_start;
 wire kernel_rst_n;
 localparam integer TRIAL_TICK_WIDTH=$clog2(CLOCK_HZ);
 logic [TRIAL_TICK_WIDTH-1:0] trial_tick;
 logic [4:0] trial_seconds;
 wire core_rst_n=rst_n&&running;
 assign kernel_rst_n=core_rst_n&&!round_reset;
 wire command_ready;wire receiver_command_valid=state==1||state==3||state==5||state==7;
 wire [7:0] command_data=state==1 ? 8'h76:state==3 ? 8'h64:state==5 ? 8'h62:8'h73; // v, d, b; S4 sends s
 uart_tx #(.CLOCK_HZ(CLOCK_HZ),.BAUD(BAUD)) commands(clk,rst_n,receiver_command_valid,command_data,command_ready,receiver_tx);
 wire byte_valid,byte_error;wire [7:0] byte_data;
 uart_rx #(.CLOCK_HZ(CLOCK_HZ),.BAUD(BAUD)) serial_rx(clk,rst_n,receiver_rx,byte_valid,byte_error,byte_data);
 assign eeg_byte_valid=byte_valid;assign eeg_byte_error=byte_error;assign eeg_byte_data=byte_data;
 wire sample_valid,sample_ready,overrun;wire signed [31:0] s0,s1,s2,s3;
 wire [15:0] sequence_number,rx_gap_over_5ms,rx_gap_over_50ms;wire [31:0] malformed,gaps;
 wire [7:0] rx_timeout_errors,rx_footer_errors;
 cyton_daisy_rx #(.CLOCK_HZ(CLOCK_HZ)) parser(clk,core_rst_n,byte_valid,byte_error,byte_data,
  sample_valid,sample_ready,s0,s1,s2,s3,sequence_number,overrun,malformed,rx_gap_over_5ms,
  rx_gap_over_50ms,rx_timeout_errors,rx_footer_errors);
 wire observer_eligible;
 wire active,result_valid,check_valid,numeric_fault,live_update,live_match;
 wire [1:0] result_kind,confirmations;wire [2:0] result_label,live_label;
 wire [3:0] mask;wire [15:0] check_seq,hardware_phase;
 wire signed [63:0] score0,score1,score2,score3,score4;
 ssvep_live_kernel #(.CLOCK_HZ(CLOCK_HZ)) kernel(
  .clk(clk),.rst_n(kernel_rst_n),.start(core_start),.cca_method(1'b0), // FBCCA; FBTCCA local branch disabled
  .confirmation_clear(CONTINUOUS_MODE&&page_restart),
  .sample_valid(sample_valid),.sample_ready(sample_ready),.sample0(s0),.sample1(s1),.sample2(s2),.sample3(s3),
  .sample_bad(4'd0),.sample_sequence(sequence_number),.ingress_overrun(overrun),.fifth_enabled(ui_page==0),
  .active(active),.result_valid(result_valid),.result_kind(result_kind),.result_label(result_label),
  .check_valid(check_valid),.score0(score0),.score1(score1),.score2(score2),.score3(score3),.score4(score4),
  .channel_mask(mask),.check_sequence_number(check_seq),.numeric_fault(numeric_fault),.gap_count(gaps),
  .confirmations(confirmations),.debug_pc(hardware_phase),.live_update(live_update),.live_match(live_match),.live_label(live_label),
  .debug_raw_check(),.debug_rebase(),.debug_engine_ready(),.debug_fifo_count(),.debug_epoch(),.debug_eligible(observer_eligible));
 assign ui_state=fault?3'd6:trial_running?3'd2:
  ((state>=1&&state<=5)||state==9||state==10)?3'd1:
  trial_done?(display_code!=0?3'd3:state==8?3'd5:3'd4):3'd0;
 assign stream_on=running;
 assign signal_fresh=running&&fresh_count<CLOCK_HZ*3/4;
 logic ingress_fault;
 logic [31:0] previous_malformed;
 assign fault=startup_fault||(running&&(numeric_fault||ingress_fault));
 assign command_code=display_code;
 logic [15:0] last_sequence;logic have_sequence;
 always_ff @(posedge clk)begin
  if(!rst_n)begin startup_fault<=0;reply_dollars<=0;state<=0;wait_count<=0;running<=0;core_start<=0;display_code<=0;
   fresh_count<=CLOCK_HZ;last_sequence<=0;have_sequence<=0;
   trial_armed<=AUTO_MODE;trial_running<=0;trial_done<=0;trial_tick<=0;trial_seconds<=0;round_reset<=0;cooldown<=0;retry_count<=0;
   command_valid<=0;ingress_fault<=0;previous_malformed<=0;target_latched<=0;latched_target<=0;end
  else begin
   core_start<=0;command_valid<=0;previous_malformed<=malformed;
   if(!running)begin fresh_count<=CLOCK_HZ;have_sequence<=0;end
   else if(fresh_count<CLOCK_HZ)fresh_count<=fresh_count+1'b1;
   if(sample_valid)begin fresh_count<=0;last_sequence<=sequence_number;have_sequence<=1;end
   if(CONTINUOUS_MODE)begin
    // Directions renew on every validated confirmation. Function keys are short
    // presses: one event per confirmed target until invalidated or changed.
    if(trial_running&&live_update&&signal_fresh&&!fault&&!overrun&&!numeric_fault&&
       !(sample_valid&&have_sequence&&sequence_number!=last_sequence+16'd1))begin
     if(live_match)begin
      display_code<=live_label+3'd1;
      if((SAME_TARGET_RETRIGGER&&ui_page==0)||!target_latched||live_label!=latched_target)command_valid<=1;
      target_latched<=1;latched_target<=live_label;
     end else begin display_code<=0;if(ui_page!=0)target_latched<=0;end
    end
    if(!running||!signal_fresh||fault)begin target_latched<=0;display_code<=0;end
   end else if(trial_running&&!trial_done)begin
     if(trial_tick==CLOCK_HZ-1)begin trial_tick<=0;trial_seconds<=trial_seconds+1'b1;end
     else trial_tick<=trial_tick+1'b1;
     if(trial_seconds==17&&trial_tick==CLOCK_HZ-1)begin trial_done<=1;trial_running<=0;display_code<=0;end
     else if(live_update&&live_match&&signal_fresh&&!fault&&!overrun&&!numeric_fault&&
             !(sample_valid&&have_sequence&&sequence_number!=last_sequence+16'd1))begin
       display_code<=live_label+3'd1;trial_done<=1;trial_running<=0;command_valid<=1;
     end
     else if(numeric_fault)begin trial_done<=1;trial_running<=0;display_code<=0;end
   end
   // Original PC startup: reset v, wait $$$, defaults d, wait $$$, start b.
   // UART RX remains active here; EEG parser/kernel stay reset until b.
   case(state)
    0:if(wait_count>=BOOT_CYCLES-1)begin wait_count<=0;reply_dollars<=0;state<=1;end else wait_count<=wait_count+1'b1;
    1:if(command_ready)begin state<=2;wait_count<=0;reply_dollars<=0;end
    2,4:begin
      if(wait_count>=REPLY_TIMEOUT-1)begin
       state<=11;startup_fault<=1;running<=0;trial_armed<=0;trial_running<=0;trial_done<=1;display_code<=0;command_valid<=0;
      end else begin
       wait_count<=wait_count+1'b1;
       if(byte_error)reply_dollars<=0;
       else if(byte_valid)begin
        if(byte_data==8'h24)begin
         if(reply_dollars==2)begin state<=state==2 ? 9:10;wait_count<=0;reply_dollars<=0;end
         else reply_dollars<=reply_dollars+1'b1;
        end else reply_dollars<=0;
       end
      end
    end
    9:if(wait_count>=COMMAND_GAP-1)begin wait_count<=0;state<=3;end else wait_count<=wait_count+1'b1;
    3:if(command_ready)begin state<=4;wait_count<=0;reply_dollars<=0;end
    10:if(wait_count>=COMMAND_GAP-1)begin wait_count<=0;state<=5;end else wait_count<=wait_count+1'b1;
    5:if(command_ready)begin
      state<=6;running<=1;round_reset<=0;
      if(trial_armed)begin core_start<=1;trial_running<=1;trial_armed<=0;trial_tick<=0;trial_seconds<=0;end
    end
    6:if(!CONTINUOUS_MODE&&AUTO_MODE&&trial_done&&!fault)begin
       if(cooldown<COOLDOWN_CYCLES)cooldown<=cooldown+1'b1;
       else if(!round_reset)round_reset<=1;
       else begin round_reset<=0;core_start<=1;trial_running<=1;trial_done<=0;trial_tick<=0;trial_seconds<=0;cooldown<=0;display_code<=0;end
    end
    7:if(command_ready)state<=8;
    8,11:;
    default:state<=0;
   endcase
   // Cancel the session on a UART/frame/sequence/numeric fault, including after confirmation.
   if(running&&(byte_error||overrun||numeric_fault||malformed!=previous_malformed||
      (sample_valid&&have_sequence&&sequence_number!=last_sequence+16'd1)))begin
    ingress_fault<=1;command_valid<=0;trial_running<=0;trial_armed<=0;trial_done<=1;
   end
   if(AUTO_MODE&&page_restart&&running&&!fault)begin
    if(!CONTINUOUS_MODE)begin trial_running<=0;trial_done<=1;end
    command_valid<=0;display_code<=0;cooldown<=0;target_latched<=0;
   end
   if(!trial_done)cooldown<=0;
   if(AUTO_MODE&&(state==11||(state==6&&fault)))begin
    if(retry_count>=RETRY_CYCLES-1)begin
     retry_count<=0;startup_fault<=0;ingress_fault<=0;running<=0;state<=1;wait_count<=0;reply_dollars<=0;
     trial_armed<=1;trial_running<=0;trial_done<=0;display_code<=0;
    end else retry_count<=retry_count+1'b1;
   end else retry_count<=0;
   // S1 restarts the whole receiver/session state. S4 stops stream and display.
   if(start_press)begin target_latched<=0;startup_fault<=0;reply_dollars<=0;command_valid<=0;ingress_fault<=0;previous_malformed<=0;running<=0;display_code<=0;state<=1;wait_count<=0;
     trial_armed<=1;trial_running<=0;trial_done<=0;trial_tick<=0;trial_seconds<=0;end
   if(stop_press)begin target_latched<=0;startup_fault<=0;reply_dollars<=0;command_valid<=0;ingress_fault<=0;running<=0;display_code<=0;state<=7;wait_count<=0;
     trial_armed<=0;trial_running<=0;trial_done<=0;trial_tick<=0;trial_seconds<=0;end
  end
 end
 // Keep the assigned diagnostic pin at UART idle.
 assign diagnostic_tx=1'b1;
endmodule
