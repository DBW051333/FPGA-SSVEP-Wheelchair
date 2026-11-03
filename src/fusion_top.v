module fusion_top #(parameter AUTO_MODE=1,CONTINUOUS_MODE=1,SAME_TARGET_RETRIGGER=1,ACTION_CYCLES=150000000,KEY_CYCLES=25000000)(input clk,input rst_n,input [1:0] key_n,
 input receiver_rx,output receiver_tx,output diagnostic_tx,
 input panel_view_n,input page_next_n,input [5:0] sw_n,
 input mute_led,sos_led,d5,d6,ser,rclk,srclk,
 output [5:0] key_in,output dac_din,dac_sclk,dac_cs_n,
 output [3:0] led,output hdmi_oe,
 output tmds_clk_p,tmds_clk_n,output [2:0] tmds_data_p,tmds_data_n);
 wire pclk,fclk,pll_serial,locked,refclk,ref_locked;
 Reference_PLL refpll(.clkin(clk),.clkout0(refclk),.clkout1(),.lock(ref_locked),.reset(!rst_n),.mdclk(clk));
 Gowin_PLL pll(.clkin(refclk),.reset(!rst_n||!ref_locked),.clkout0(),.clkout1(pll_serial),.lock(locked),.mdclk(clk));
 // Release all four serializers while their shared HCLK is stopped. Wait 60 ns
 // before requesting clock enable; DHCE opens only after its falling-edge pipeline.
 wire clock_ready=rst_n&&ref_locked&&locked;
 (* syn_preserve=1 *) reg [2:0] clock_ready_sync;
 (* syn_preserve=1 *) reg [3:0] startup_shift;
 always @(posedge clk or negedge clock_ready)
  if(!clock_ready) begin clock_ready_sync<=0;startup_shift<=0;end
  else begin
   clock_ready_sync<={clock_ready_sync[1:0],1'b1};
   if(!clock_ready_sync[2]) startup_shift<=0;
   else startup_shift<={startup_shift[2:0],1'b1};
  end
 wire serializer_reset=!startup_shift[0];
 wire serial_enable=startup_shift[3];
 DHCE serial_gate(.CLKIN(pll_serial),.CEN(!serial_enable),.CLKOUT(fclk));
 // One hardware divide-by-five defines the pixel boundary for all four OSER10s.
 CLKDIV pixel_div(.HCLKIN(fclk),.RESETN(!serializer_reset),.CALIB(1'b0),.CLKOUT(pclk));
 defparam pixel_div.DIV_MODE="5";
 // Assert asynchronously on loss of lock; release synchronously in each domain.
 wire reset_request=clock_ready&&serial_enable;
 (* syn_preserve=1 *) reg [3:0] reset_sync;
 always @(posedge pclk or negedge reset_request)
  if(!reset_request) reset_sync<=0;else reset_sync<={reset_sync[2:0],1'b1};
 wire pixel_rst_n=reset_sync[3];

 assign hdmi_oe=1'b1;
 (* syn_preserve=1 *) reg [3:0] system_reset_sync;
 wire compute_clock_ready=rst_n&&ref_locked;
 always @(posedge refclk or negedge compute_clock_ready)
  if(!compute_clock_ready)system_reset_sync<=0;else system_reset_sync<={system_reset_sync[2:0],1'b1};
 wire system_rst_n=system_reset_sync[3];
 wire start_press,stop_press,page_cancel,round_start;
 (* syn_keep=1 *) wire next_press;
 wire [1:0] page,session_page;
 wire [2:0] ui_state,panel_command;wire direction_valid,panel_valid;
 wire [2:0] direction_code;
 key_filter #(.DEBOUNCE_CYCLES(540000)) start_key(refclk,system_rst_n,key_n[0],start_press);
 key_filter #(.DEBOUNCE_CYCLES(540000)) stop_key(refclk,system_rst_n,key_n[1],stop_press);
 // S2 (panel_view_n) is the independent power key only; page flipping is S3-only.
 key_filter #(.DEBOUNCE_CYCLES(540000)) next_key(refclk,system_rst_n,page_next_n,next_press);
 // Capture even a sub-debounce stop. Only a new S1 can release cancellation.
 (* syn_preserve=1 *) reg session_cancelled=1;
 (* syn_preserve=1, ASYNC_REG="TRUE" *) reg cancel_meta,cancel_sync;
 reg cancellation_seen;
 always @(posedge refclk or negedge system_rst_n or negedge key_n[1])
  if(!system_rst_n||!key_n[1])session_cancelled<=1;
  else if(AUTO_MODE&&round_start)session_cancelled<=0;
  else if(page_cancel&&!AUTO_MODE)session_cancelled<=1;
  else if(start_press)session_cancelled<=0;
 always @(posedge refclk)
  if(!system_rst_n)begin cancel_meta<=1;cancel_sync<=1;cancellation_seen<=1;end
  else begin cancel_meta<=session_cancelled;cancel_sync<=cancel_meta;cancellation_seen<=cancel_sync;end
 wire stop_request=stop_press||(!AUTO_MODE&&page_cancel)||(cancel_sync&&!cancellation_seen);
 wire eeg_byte_valid,eeg_byte_error;wire [7:0] eeg_byte_data;
 wire [2:0] display_code,command_code;wire command_valid;wire stream_on,signal_fresh,core_fault;
 ssvep_live_frontend #(.CLOCK_HZ(27000000),.AUTO_MODE(AUTO_MODE),.CONTINUOUS_MODE(CONTINUOUS_MODE),.SAME_TARGET_RETRIGGER(SAME_TARGET_RETRIGGER)) frontend(.clk(refclk),.rst_n(system_rst_n),.start_press(start_press&&!page_cancel),.stop_press(stop_request),
  .page_restart(page_cancel),.round_start(round_start),.ui_page(page),.ui_session_page(session_page),.ui_state(ui_state),
  .receiver_rx(receiver_rx),.receiver_tx(receiver_tx),.diagnostic_tx(diagnostic_tx),.display_code(display_code),
  .stream_on(stream_on),.signal_fresh(signal_fresh),.fault(core_fault),.command_valid(command_valid),.command_code(command_code),
  .eeg_byte_valid(eeg_byte_valid),.eeg_byte_error(eeg_byte_error),.eeg_byte_data(eeg_byte_data));
 page_command_router #(.AUTO_MODE(AUTO_MODE),.CONTINUOUS_MODE(CONTINUOUS_MODE)) router(.clk(refclk),.rst_n(system_rst_n),.start_press(AUTO_MODE?round_start:start_press),.stop_press(stop_press||(cancel_sync&&!cancellation_seen)),
  .next_press(next_press),.prev_press(1'b0),.result_valid(command_valid),.result_code(command_code),
  .page(page),.session_page(session_page),.cancel(page_cancel),.direction_valid(direction_valid),.direction_code(direction_code),
  .panel_valid(panel_valid),.panel_code(panel_command));
 // Raw S1/S4 assertion cancels motion before key debounce; release is synchronized.
 wire link_reset_n=!(AUTO_MODE&&round_start)&&!page_cancel&&rst_n&&key_n[0]&&key_n[1]&&!session_cancelled&&clock_ready&&stream_on&&signal_fresh&&!core_fault;
 wire [11:0] target_x,target_y;wire watchdog_fault;
 motion_link #(.PULSE_CYCLES(ACTION_CYCLES),.CONTINUOUS_MODE(CONTINUOUS_MODE),.DIRECT_EXECUTION(0)) motion(.src_clk(refclk),.clk(clk),.reset_n(link_reset_n),
  .src_valid(direction_valid),.src_command(direction_code),.target_x(target_x),.target_y(target_y),
  .direction_led(led),.watchdog_fault(watchdog_fault));
 dac_pair_driver dac(.clk(clk),.target_x(target_x),.target_y(target_y),
  .dac_din(dac_din),.dac_sclk(dac_sclk),.dac_cs_n(dac_cs_n));
 wire [5:0] gaze_keys;wire key_watchdog_fault;
 panel_key_link #(.PULSE_CYCLES(KEY_CYCLES),.CONTINUOUS_MODE(CONTINUOUS_MODE),.DIRECT_EXECUTION(0)) key_link(.src_clk(refclk),.clk(clk),.reset_n(link_reset_n),.src_valid(panel_valid),
  .src_command(panel_command),.key_pulse(gaze_keys),.watchdog_fault(key_watchdog_fault));
 // Panel and display use the independent 50MHz domain.
 (* syn_preserve=1 *) reg [15:0] panel_reset_sync=0;
 wire panel_reset_request=rst_n&&key_n[1];
 always @(posedge clk or negedge panel_reset_request)
  if(!panel_reset_request)panel_reset_sync<=0;
  else panel_reset_sync<={panel_reset_sync[14:0],1'b1};
 wire panel_rst_n=panel_reset_sync[15];
 wire [11:0] panel_leds;wire panel_direct_valid,panel_serial_valid;
 panel_reader panel(.clk(clk),.rst_n(panel_rst_n),.mute_led(mute_led),.sos_led(sos_led),
  .d5(d5),.d6(d6),.ser(ser),.rclk(rclk),.srclk(srclk),.led_on(panel_leds),
  .direct_valid(panel_direct_valid),.serial_valid(panel_serial_valid));
 (* syn_preserve=1, ASYNC_REG="TRUE" *) reg [5:0] sw_meta,sw_sync;
 reg [5:0] switch_armed;reg [2:0] switch_prime;
 always @(posedge clk or negedge panel_rst_n)
  if(!panel_rst_n)begin sw_meta<=0;sw_sync<=0;switch_armed<=0;switch_prime<=0;end
  else begin
   sw_meta<=sw_n;sw_sync<=sw_meta;
   if(switch_prime!=7)switch_prime<=switch_prime+1'b1;
   else switch_armed<=switch_armed|~sw_sync;
  end
 // S2 (panel_view_n) = 开机：消抖后按下即置位，松开复位；复位/停止后需松开再按才重新触发。
 // 无长按/短按区分。
 wire s2_press;
 key_filter #(.DEBOUNCE_CYCLES(540000)) s2_key(clk,panel_rst_n,panel_view_n,s2_press);
 (* syn_preserve=1 *) reg s2_release_meta,s2_release_sync;
 reg s2_power,s2_armed;
 always @(posedge clk or negedge panel_rst_n)
  if(!panel_rst_n)begin s2_release_meta<=0;s2_release_sync<=0;s2_power<=0;s2_armed<=0;end
  else begin
   s2_release_meta<=panel_view_n;s2_release_sync<=s2_release_meta;
   if(s2_release_sync) s2_armed<=1;
   if(s2_press&&s2_armed)begin s2_power<=1;s2_armed<=0;end
   else if(s2_release_sync) s2_power<=0;
  end
 assign key_in=panel_rst_n?((sw_sync&switch_armed)|gaze_keys|{5'b0,s2_power}):6'b0;
 wire [11:0] x;wire [10:0] y;wire hs,vs,de,frame_tick;
 video_timing timing(pclk,pixel_rst_n,x,y,de,hs,vs,frame_tick);
 wire [4:0] bright;wire [39:0] luminance;
 ssvep_stimulus stim(pclk,pixel_rst_n,frame_tick,bright,luminance);
 reg [11:0] canvas_x;reg [10:0] canvas_y;
 always @(posedge pclk or negedge pixel_rst_n)
  if(!pixel_rst_n)begin canvas_x<=0;canvas_y<=0;end
  else begin canvas_x<=(x<12'd1280) ? (12'd1279-x) : 12'd0;canvas_y<=(y<11'd720) ? (11'd719-y) : 11'd0;end
 wire [23:0] rgb,panel_status_data,pixel_status;
 wire [6:0] attention_score;wire attention_valid,metrics_stream,metrics_fresh,metrics_fault;
 wire [1:0] emotion_label;wire [2:0] emotion_state;
 eeg_metrics #(.CLOCK_HZ(27000000)) metrics(.clk(refclk),.rst_n(system_rst_n),.running(stream_on),
  .byte_valid(eeg_byte_valid),.byte_error(eeg_byte_error),.byte_data(eeg_byte_data),
  .score(attention_score),.valid(attention_valid),.stream_on(metrics_stream),
  .signal_fresh(metrics_fresh),.fault(metrics_fault),.emotion_label(emotion_label),.emotion_state(emotion_state));
 wire [23:0] metrics_source={attention_score,attention_valid,metrics_stream,metrics_fresh,9'd0,emotion_state,emotion_label};
 wire [33:0] pixel_ui;
 panel_status status_decode(panel_leds,panel_direct_valid,panel_serial_valid,panel_status_data);
 // Both mailbox endpoints reset together on loss of either clock/reset.
 wire status_reset_request=pixel_rst_n&&panel_rst_n&&system_rst_n;
 reg [1:0] status_src_reset,status_ref_reset,status_dst_reset;
 always @(posedge clk or negedge status_reset_request)
  if(!status_reset_request)status_src_reset<=0;else status_src_reset<={status_src_reset[0],1'b1};
 always @(posedge refclk or negedge status_reset_request)
  if(!status_reset_request)status_ref_reset<=0;else status_ref_reset<={status_ref_reset[0],1'b1};
 always @(posedge pclk or negedge status_reset_request)
  if(!status_reset_request)status_dst_reset<=0;else status_dst_reset<={status_dst_reset[0],1'b1};
 status_cdc vehicle_cdc(clk,status_src_reset[1],panel_status_data,pclk,status_dst_reset[1],frame_tick,pixel_status);
 status_cdc #(.WIDTH(34)) result_cdc(refclk,status_ref_reset[1],{metrics_source,page,session_page,ui_state,display_code},pclk,status_dst_reset[1],frame_tick,pixel_ui);
 paged_dashboard dashboard(pclk,pixel_rst_n,canvas_x,canvas_y,bright,pixel_ui[9:8],pixel_ui[7:6],pixel_ui[5:3],pixel_ui[2:0],pixel_status,rgb,luminance,pixel_ui[33:10]);
 // Two extra sync stages match the dashboard's added tile-geometry and
 // glyph-address pipeline stages, keeping RGB and blanking aligned.
 reg [7:0] hs_pipe,vs_pipe,de_pipe;
 always @(posedge pclk or negedge pixel_rst_n)
  if(!pixel_rst_n)begin hs_pipe<=0;vs_pipe<=0;de_pipe<=0;end
  else begin hs_pipe<={hs_pipe[6:0],hs};vs_pipe<={vs_pipe[6:0],vs};de_pipe<={de_pipe[6:0],de};end
 tmds_tx tx(pclk,fclk,pixel_rst_n,rgb,hs_pipe[7],vs_pipe[7],de_pipe[7],
  tmds_clk_p,tmds_clk_n,tmds_data_p,tmds_data_n,serializer_reset);
endmodule
