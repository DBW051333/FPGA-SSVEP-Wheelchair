// Five-stage pixel pipeline. Only shifts, compares and narrow additions in geometry.
module paged_dashboard(input wire clk,rst_n,input wire [11:0] x,input wire [10:0] y,
 input wire [4:0] bright,input wire [1:0] page,session_page,
 input wire [2:0] ui_state,result_code,input wire [23:0] status,
 output reg [23:0] rgb,input wire [39:0] luminance,input wire [23:0] metrics);
 wire [6:0] attention_score=metrics[23:17];
 wire attention_valid=metrics[16],stream_on=metrics[15],signal_fresh=metrics[14];
 wire [2:0] emotion_state=metrics[4:2];wire [1:0] emotion_label=metrics[1:0];
 (* syn_romstyle="block_rom" *) reg [7:0] texts[0:2047];initial $readmemh("assets/dashboard_text_compact.hex",texts);
 function automatic [5:0] target_text(input [1:0] pg,input [2:0] target);
  begin target_text=target==4||target==3&&pg!=0?23:pg==0?13+target:pg==1?(target==2?21:17+target):(target==2?22:19+target);end
 endfunction
 function automatic icon(input [3:0] kind,input [5:0] u,v);
  reg [5:0] a,b;reg shaft,head,outline,dots,selected;
  begin
   a=u;b=v;
   if(kind==1)b=63-v;
   if(kind==2)begin a=v;b=u;end
   if(kind==3)begin a=v;b=63-u;end
   shaft=a>=28&&a<36&&b>=23&&b<56;
   head=b>=8&&b<32&&a+{1'b0,b}>=40&&a<=b+24;
   outline=(u>=4&&u<60&&v>=5&&v<59)&&!(u>=8&&u<56&&v>=9&&v<55);
   dots=((u>=12&&u<25)||(u>=39&&u<52))&&((v>=14&&v<27)||(v>=37&&v<50));
   selected=kind==4 ? u>=26&&u<38&&v>=43&&v<53:
            kind==5 ? u>=26&&u<38&&v>=28&&v<38:
            kind==6 ? u>=12&&u<25&&v>=24&&v<38:u>=39&&u<52&&v>=24&&v<38;
   if(kind<4)icon=shaft||head;
   else if(kind<8)icon=outline||selected||(dots&&((u==12||u==24||u==39||u==51)||(v==14||v==26||v==37||v==49)));
   else if(kind==8)icon=(u>=8&&u<22&&v>=24&&v<40)||
     (u>=20&&u<34&&v>=12&&v<52&&u+v>=44&&v<=u+20)||
     (u>=39&&u<58&&v>=20&&v<44&&((u+v>=76&&u+v<=82)||(u>=v+14&&u<=v+20)));
   else if(kind==9)icon=outline||(u>=26&&u<38&&v>=15&&v<49)||(u>=15&&u<49&&v>=26&&v<38);
   else if(kind==10)icon=outline||(v>=28&&v<36&&u>=16&&u<48)||(u>=34&&u<50&&v>=18&&v<46&&u+v>=60&&u<=v+20);
   else if(kind==11)icon=(u>=28&&u<36&&v>=8&&v<35)||((outline)&&(v>=22));
   else if(kind==12)icon=(u>=10&&u<22&&v>=24&&v<40)||(u>=20&&u<44&&v>=12&&v<52&&u+v>=44&&v<=u+20);
   else if(kind==13)icon=(u>=28&&u<36&&v>=12&&v<52)||(u>=12&&u<52&&v>=28&&v<36);
   else if(kind==14)icon=u>=12&&u<52&&v>=28&&v<36;
   else icon=0;
  end
 endfunction
 // ---- Stage 0: register coordinates and tile geometry. This breaks the long
 // x/y -> ox(=x-LEFT) -> text-id cone into two short registered halves.
 reg [11:0] x_q;reg [10:0] y_q;reg [2:0] tile_q;reg [8:0] ox_q;reg [7:0] oy_q;reg active_tile_q;
 reg [8:0] bar_right_q;
 always @(posedge clk or negedge rst_n)
  if(!rst_n)begin x_q<=0;y_q<=0;tile_q<=0;ox_q<=0;oy_q<=0;active_tile_q<=0;bar_right_q<=0;end
  else begin
   x_q<=x;y_q<=y;tile_q<=0;ox_q<=0;oy_q<=0;active_tile_q<=0;
   bar_right_q<=93+((attention_score*5)>>1);
   if(x>=486&&x<794&&y>=72&&y<216)begin tile_q<=0;ox_q<=x-486;oy_q<=y-72;active_tile_q<=1;end
   if(x>=486&&x<794&&y>=504&&y<648)begin tile_q<=1;ox_q<=x-486;oy_q<=y-504;active_tile_q<=1;end
   if(x>=64&&x<372&&y>=288&&y<432)begin tile_q<=2;ox_q<=x-64;oy_q<=y-288;active_tile_q<=1;end
   if(x>=908&&x<1216&&y>=288&&y<432)begin tile_q<=3;ox_q<=x-908;oy_q<=y-288;active_tile_q<=1;end
   if(page==0&&x>=486&&x<794&&y>=288&&y<432)begin tile_q<=4;ox_q<=x-486;oy_q<=y-288;active_tile_q<=1;end
  end
 reg [23:0] bg,fg;reg text_on,lookup;reg [5:0] text_id;reg [7:0] direct_char;
 // Valid tile offsets are 0..307 by 0..143. Narrow arithmetic preserves
 // every active pixel while avoiding unnecessary 32-bit geometry paths.
 integer tx_,ty_,scale,label_start;reg [7:0] tile_luma;reg [3:0] kind;reg icon_on;
 always @*begin
  bg=24'h0D1825;fg=24'hE8F2FA;text_on=0;lookup=1;text_id=0;direct_char=0;tx_=0;ty_=0;scale=1;
  tile_luma=0;label_start=80;kind=10;icon_on=0;
  if(y_q<34)begin
   bg=24'h1B3045;
   if(y_q>=8&&y_q<24)begin
    if(x_q>=24&&x_q<88)begin text_on=1;text_id=28;tx_=x_q-24;ty_=y_q-8;end
    if(x_q>=96&&x_q<112)begin text_on=1;lookup=0;direct_char=status[16]?8'd16+status[10:8]:8'd13;tx_=x_q-96;ty_=y_q-8;end
    if(x_q>=192&&x_q<256)begin text_on=1;text_id=29;tx_=x_q-192;ty_=y_q-8;end
    if(x_q>=264&&x_q<280)begin text_on=1;lookup=0;direct_char=status[17]?8'd16+status[13:11]:8'd13;tx_=x_q-264;ty_=y_q-8;end
    if(x_q>=360&&x_q<392)begin text_on=1;text_id=21;tx_=x_q-360;ty_=y_q-8;end
    if(x_q>=408&&x_q<440)begin text_on=1;text_id=!status[18]?30:status[14]?31:32;tx_=x_q-408;ty_=y_q-8;end
    if(x_q>=520&&x_q<568)begin text_on=1;text_id=22;tx_=x_q-520;ty_=y_q-8;end
    if(x_q>=584&&x_q<616)begin text_on=1;text_id=!status[19]?30:status[15]?31:32;tx_=x_q-584;ty_=y_q-8;end
    if(x_q>=928&&x_q<1216)begin text_on=1;text_id=12;tx_=x_q-928;ty_=y_q-8;fg=24'h9ED5FF;end
   end
  end
  if(active_tile_q)begin
   tile_luma=luminance[tile_q*8+:8];bg={3{tile_luma}};
   fg=tile_luma>128?24'h080808:24'hFFFFFF;
   if(ox_q<4||ox_q>=304||oy_q<4||oy_q>=140)bg=24'h5A99C6;
   kind=tile_q==4||tile_q==3&&page!=0?10:page==0?tile_q:page==1?(tile_q==0?11:tile_q==1?12:8):(tile_q==0?13:tile_q==1?14:9);
   if(ox_q>=122&&ox_q<186&&oy_q>=8&&oy_q<72)begin
    icon_on=icon(kind,ox_q-122,oy_q-8);if(icon_on)bg=fg;
   end
   label_start=page==1&&tile_q==0?106:page==2&&tile_q<2?106:122;
   if(ox_q>=label_start&&ox_q<282&&oy_q>=80&&oy_q<112)begin
    text_on=1;lookup=1;text_id=target_text(page,tile_q);tx_=ox_q-label_start;ty_=oy_q-80;scale=2;
   end
   if(ox_q>=114&&ox_q<194&&oy_q>=120&&oy_q<136)begin
    text_on=1;lookup=1;text_id=tile_q==4?48:24+tile_q;tx_=ox_q-114;ty_=oy_q-120;scale=1;
   end
  end
  // Recognition information sits above/below the central 17 Hz tile.
  // It must never overwrite the center stimulus, including its dark phase.
  if(x_q>=352&&x_q<928&&y_q>=220&&y_q<280)begin
   bg=24'h15283B;fg=24'hE8F2FA;
   if(x_q>=384&&x_q<896&&y_q>=224&&y_q<256)begin
    text_on=1;text_id=page==0?1:page==1?2:3;tx_=x_q-384;ty_=y_q-224;scale=2;
   end
   if(x_q>=384&&x_q<800&&y_q>=260&&y_q<276)begin
    text_on=1;text_id=ui_state==0?4:ui_state==1?5:ui_state==2?6:ui_state==3?43:ui_state==4?44:ui_state==5?45:46;
    tx_=x_q-384;ty_=y_q-260;scale=1;fg=ui_state==2?24'h72E1BA:ui_state==1?24'hFFD079:ui_state==6?24'hFF8585:24'hB8CBDB;
   end
   if(x_q>=832&&x_q<912&&y_q>=260&&y_q<276)begin text_on=1;text_id=36+page;tx_=x_q-832;ty_=y_q-260;scale=1;fg=24'h91AEC6;end
  end
  if(x_q>=352&&x_q<928&&y_q>=436&&y_q<500)begin
   bg=24'h15283B;fg=24'hE8F2FA;
   if(x_q>=384&&x_q<448&&y_q>=442&&y_q<458)begin text_on=1;text_id=33;tx_=x_q-384;ty_=y_q-442;scale=1;end
   if(x_q>=464&&x_q<896&&y_q>=442&&y_q<458)begin
    text_on=1;text_id=result_code>=1&&result_code<=5&&page==session_page?target_text(session_page,result_code-1):39;
    tx_=x_q-464;ty_=y_q-442;scale=1;fg=24'h83D7FF;
   end
   if(x_q>=384&&x_q<896&&y_q>=466&&y_q<482)begin text_on=1;text_id=11;tx_=x_q-384;ty_=y_q-466;scale=1;fg=24'hBDD1E1;end
   if(x_q>=384&&x_q<896&&y_q>=484&&y_q<500)begin text_on=1;text_id=page==0?49:47;tx_=x_q-384;ty_=y_q-484;scale=1;fg=24'h819CAF;end
  end
  // Both cards occupy unused corners; no stimulus or existing center panel is covered.
  // Coordinates are logical, so the top-level 180-degree mapping rotates them too.
  if(x_q>=64&&x_q<372&&y_q>=482&&y_q<650)begin
   bg=24'h15283B;fg=24'hE8F2FA;text_on=0;lookup=1;scale=1;
   if(x_q>=84&&x_q<352&&y_q>=498&&y_q<514)begin text_on=1;text_id=50;tx_=x_q-84;ty_=y_q-498;end
   if(x_q>=88&&x_q<344&&y_q>=538&&y_q<570)begin
    text_on=1;lookup=0;scale=2;tx_=(x_q-88)%32;ty_=y_q-538;fg=attention_valid?24'h72E1BA:24'hB8CBDB;
    case((x_q-88)/32)
     0:direct_char=attention_valid?(attention_score==100?8'd17:8'd0):8'd13;
     1:direct_char=attention_valid?8'd16+(attention_score/10)%10:8'd13;
     2:direct_char=attention_valid?8'd16+attention_score%10:8'd13;
     3:direct_char=0;4:direct_char=15;5:direct_char=17;default:direct_char=16;
    endcase
   end
   if(x_q>=93&&x_q<343&&y_q>=590&&y_q<602)begin bg=24'h30495C;
    if(attention_valid&&x_q<93+((attention_score*5)>>1))bg=24'h72E1BA;end
   if(x_q>=84&&x_q<352&&y_q>=622&&y_q<638)begin text_on=1;lookup=1;scale=1;
    text_id=attention_valid?59:!stream_on?55:!signal_fresh?58:56;tx_=x_q-84;ty_=y_q-622;fg=24'h9ED5FF;end
  end
  if(x_q>=908&&x_q<1216&&y_q>=482&&y_q<650)begin
   bg=24'h15283B;fg=24'hE8F2FA;text_on=0;lookup=1;scale=1;
   if(x_q>=928&&x_q<1196&&y_q>=498&&y_q<514)begin text_on=1;text_id=51;tx_=x_q-928;ty_=y_q-498;end
   if(x_q>=944&&x_q<1200&&y_q>=538&&y_q<570)begin text_on=1;scale=2;
    text_id=emotion_state==3?52+emotion_label:emotion_state==0?55:emotion_state==1?56:emotion_state==2?57:58;
    tx_=x_q-944;ty_=y_q-538;fg=emotion_state==3?24'h72E1BA:24'hB8CBDB;end
   if(x_q>=928&&x_q<1196&&y_q>=622&&y_q<638)begin text_on=1;scale=1;text_id=60;tx_=x_q-928;ty_=y_q-622;fg=24'h9ED5FF;end
  end
 end
 // These regions are disjoint (the two panel rectangles share one color).
 // Select backgrounds using one-hot terms.
 wire bg_header=y_q<34;
 wire bg_bar=x_q>=93&&x_q<343&&y_q>=590&&y_q<602;
 wire bg_panel=((x_q>=352&&x_q<928&&((y_q>=220&&y_q<280)||(y_q>=436&&y_q<500)))||
                (((x_q>=64&&x_q<372)||(x_q>=908&&x_q<1216))&&y_q>=482&&y_q<650))&&!bg_bar;
 // Decode each tile independently. Avoid coordinates -> selected tile offset
 // -> icon -> background in one long combinational path.
 wire [4:0] background_hit;
 wire [23:0] background_color[0:4];
 genvar bg_i;
 generate for(bg_i=0;bg_i<5;bg_i=bg_i+1)begin:parallel_background
  localparam integer LEFT=bg_i==2?64:bg_i==3?908:486;
  localparam integer TOP=bg_i==0?72:bg_i==1?504:288;
  wire [7:0] light=luminance[bg_i*8+:8];
  wire [3:0] shape=bg_i==4||(bg_i==3&&page!=0)?10:
    page==0?bg_i:page==1?(bg_i==0?11:bg_i==1?12:8):(bg_i==0?13:bg_i==1?14:9);
  wire edge_on=x_q<LEFT+4||x_q>=LEFT+304||y_q<TOP+4||y_q>=TOP+140;
  wire icon_window=x_q>=LEFT+122&&x_q<LEFT+186&&y_q>=TOP+8&&y_q<TOP+72;
  reg hit0,edge0,window0;reg [3:0] shape0;reg [5:0] u0,v0;reg [7:0] light0;
  always @(posedge clk or negedge rst_n)
   if(!rst_n)begin hit0<=0;edge0<=0;window0<=0;shape0<=0;u0<=0;v0<=0;light0<=0;end
   else begin
    hit0<=(bg_i!=4||page==0)&&x_q>=LEFT&&x_q<LEFT+308&&y_q>=TOP&&y_q<TOP+144;
    edge0<=edge_on;window0<=icon_window;shape0<=shape;
    u0<=x_q-(LEFT+122);v0<=y_q-(TOP+8);light0<=light;
   end
  assign background_hit[bg_i]=hit0;
  assign background_color[bg_i]=edge0?24'h5A99C6:
    (window0&&icon(shape0,u0,v0))?(light0>128?24'h080808:24'hFFFFFF):{3{light0}};
 end endgenerate
 wire bg_target=|background_hit;
 wire bg_default=!(bg_header||bg_bar||bg_panel);
 wire [23:0] target_background=({24{background_hit[0]}}&background_color[0])|
  ({24{background_hit[1]}}&background_color[1])|({24{background_hit[2]}}&background_color[2])|
  ({24{background_hit[3]}}&background_color[3])|({24{background_hit[4]}}&background_color[4]);
 wire [23:0] bar_background=attention_valid&&x_q<bar_right_q?24'h72E1BA:24'h30495C;
 wire [23:0] fast_background=({24{bg_header}}&24'h1B3045)|
  ({24{bg_bar}}&bar_background)|({24{bg_panel}}&24'h15283B)|({24{bg_default}}&24'h0D1825);
 reg [10:0] addr0;reg [7:0] direct0,ch1;reg lookup0,t0,t1,t2,t3,ink3;
 reg [3:0] row0,row1,col0,col1,col2;wire [15:0] font2;
 dashboard_compact_font font_store(clk,{ch1,row1},font2);
 // Every active text rectangle fits at most 32 glyph columns. Concatenation
 // is equivalent to the former wide addition for all displayed characters.
 reg [5:0] text_id_a;reg [10:0] tx_a;reg [9:0] ty_a;
 reg scale2_a,lookup_a,text_on_a,bg_hit_a;
 reg [7:0] direct_a;reg [23:0] fg_a,bg_a,target_bg_a;
 reg [23:0] bg0,bg1,bg2,bg3,fg0,fg1,fg2,fg3;
 always @(posedge clk or negedge rst_n)
  if(!rst_n)begin
   text_id_a<=0;tx_a<=0;ty_a<=0;scale2_a<=0;lookup_a<=0;text_on_a<=0;bg_hit_a<=0;
   direct_a<=0;fg_a<=0;bg_a<=0;target_bg_a<=0;
   addr0<=0;direct0<=0;ch1<=0;lookup0<=0;t0<=0;t1<=0;t2<=0;t3<=0;ink3<=0;
   row0<=0;row1<=0;col0<=0;col1<=0;col2<=0;
   bg0<=0;bg1<=0;bg2<=0;bg3<=0;fg0<=0;fg1<=0;fg2<=0;fg3<=0;rgb<=0;
  end else begin
   // Stage A: register the decoded geometry (text id, local x/y, scale, color).
   text_id_a<=text_id;tx_a<=tx_;ty_a<=ty_;scale2_a<=(scale==2);
   lookup_a<=lookup;text_on_a<=text_on;direct_a<=direct_char;
   fg_a<=fg;bg_a<=fast_background;bg_hit_a<=bg_target;target_bg_a<=target_background;
   // Stage B: glyph address from registered geometry.
   addr0<={text_id_a,scale2_a?tx_a[9:5]:tx_a[8:4]};direct0<=direct_a;lookup0<=lookup_a;
   row0<=scale2_a?(ty_a>>1):ty_a;col0<=scale2_a?(tx_a>>1):tx_a;
   t0<=text_on_a;bg0<=bg_a;fg0<=fg_a;
   // Stage C (was stage 2).
   ch1<=lookup0?texts[addr0]:direct0;row1<=row0;col1<=col0;t1<=t0;bg1<=bg_hit_a?target_bg_a:bg0;fg1<=fg0;
   col2<=col1;t2<=t1;bg2<=bg1;fg2<=fg1;
   ink3<=t2&&font2[15-col2];t3<=t2;bg3<=bg2;fg3<=fg2;
   rgb<=ink3?fg3:bg3;
  end
endmodule
