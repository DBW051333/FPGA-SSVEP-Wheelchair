// The same one-shot/heartbeat mailbox contract as the direction motion link.
// Six digital keys; normal pulse 500ms, never interpreted as an axis direction.
module panel_key_link #(parameter integer PULSE_CYCLES=25000000,HEARTBEAT_CYCLES=27000,WATCHDOG_CYCLES=500000,CONTINUOUS_MODE=0,DIRECT_EXECUTION=0)(
 input wire src_clk,clk,reset_n,src_valid,input wire [2:0] src_command,
 output reg [5:0] key_pulse,output reg watchdog_fault);
 (* syn_preserve=1 *) reg [2:0] src_reset_sync=0,dst_reset_sync=0;
 always @(posedge src_clk or negedge reset_n)
  if(!reset_n)src_reset_sync<=0;else src_reset_sync<={src_reset_sync[1:0],1'b1};
 always @(posedge clk or negedge reset_n)
  if(!reset_n)dst_reset_sync<=0;else dst_reset_sync<={dst_reset_sync[1:0],1'b1};
 wire srst=src_reset_sync[2],drst=dst_reset_sync[2];
 reg request,acknowledge;reg [2:0] held_command,pending_command;reg pending_valid;
 (* syn_preserve=1,ASYNC_REG="TRUE" *) reg ack_meta,ack_sync,req_meta,req_sync,req_settle;
 (* syn_preserve=1,ASYNC_REG="TRUE" *) reg [2:0] data_meta,data_sync;
 localparam HB_W=$clog2(HEARTBEAT_CYCLES),WD_W=$clog2(WATCHDOG_CYCLES),PULSE_W=$clog2(PULSE_CYCLES);
 reg [HB_W-1:0] heartbeat_count;reg heartbeat;
 (* syn_preserve=1,ASYNC_REG="TRUE" *) reg hb_meta,hb_sync;
 reg hb_previous,used;reg [WD_W-1:0] watchdog_count;reg [PULSE_W-1:0] remaining;
 always @(posedge src_clk or negedge srst)
  if(!srst)begin request<=0;held_command<=0;pending_command<=0;pending_valid<=0;ack_meta<=0;ack_sync<=0;heartbeat_count<=0;heartbeat<=0;end
  else begin
   ack_meta<=acknowledge;ack_sync<=ack_meta;
   if(CONTINUOUS_MODE)begin
    // Hold the in-flight payload stable; retain the newest command while busy.
    if(src_valid)begin pending_command<=src_command;pending_valid<=1;end
    if(request&&ack_sync)request<=0;
    else if(!request&&!ack_sync)begin
     if(src_valid)begin held_command<=src_command;request<=1;pending_valid<=0;end
     else if(pending_valid)begin held_command<=pending_command;request<=1;pending_valid<=0;end
    end
   end else begin
    if(request&&ack_sync)request<=0;
    else if(src_valid&&!request&&!ack_sync)begin held_command<=src_command;request<=1;end
   end
   if(heartbeat_count==HEARTBEAT_CYCLES-1)begin heartbeat_count<=0;heartbeat<=!heartbeat;end
   else heartbeat_count<=heartbeat_count+1'b1;
  end
 always @(posedge clk or negedge drst)
  if(!drst)begin
   req_meta<=0;req_sync<=0;req_settle<=0;data_meta<=0;data_sync<=0;acknowledge<=0;
   hb_meta<=0;hb_sync<=0;hb_previous<=0;watchdog_count<=0;watchdog_fault<=0;used<=0;remaining<=0;key_pulse<=0;
  end else begin
   req_meta<=request;req_sync<=req_meta;req_settle<=req_sync;data_meta<=held_command;data_sync<=data_meta;
   hb_meta<=heartbeat;hb_sync<=hb_meta;hb_previous<=hb_sync;
   if(hb_sync!=hb_previous)watchdog_count<=0;
   else if(watchdog_count!=WATCHDOG_CYCLES-1)watchdog_count<=watchdog_count+1'b1;
   if(!req_settle)acknowledge<=0;
   if(key_pulse!=0)begin if(remaining==0)key_pulse<=0;else remaining<=remaining-1'b1;end
   if(req_settle&&!acknowledge)begin
    acknowledge<=1;
    if((CONTINUOUS_MODE||!used)&&!watchdog_fault)begin
     used<=1;remaining<=PULSE_CYCLES-1;
     case(data_sync)
      1:key_pulse<=6'b000001;2:key_pulse<=6'b000010;3:key_pulse<=6'b000100;
      4:key_pulse<=6'b001000;5:key_pulse<=6'b010000;6:key_pulse<=6'b100000;
      default:key_pulse<=0;
     endcase
    end
    if(data_sync==0||data_sync>6)begin key_pulse<=0;remaining<=0;end
   end
   if(!DIRECT_EXECUTION&&(watchdog_fault||(watchdog_count==WATCHDOG_CYCLES-1&&hb_sync==hb_previous)))begin
    watchdog_fault<=1;used<=1;key_pulse<=0;
   end
  end
endmodule
