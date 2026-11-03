// debug_pc is retained at the interface and now carries a fixed hardware phase.
// Canonical 125-Hz EEG interface. Producer must retain payload until ready.
// Sequence increases by ONE per four-channel frame, including across drops.
module ssvep_live_kernel #(
    parameter integer CLOCK_HZ=50000000,
    parameter DATA_FILE="assets/data.hex"
)(
    input logic clk,rst_n,start,cca_method, // 0=FBCCA (current), 1=FBTCCA (TCCA local branch, unused)
    input wire confirmation_clear,
    input logic sample_valid,
    output wire sample_ready,
    input logic signed [31:0] sample0,sample1,sample2,sample3,
    input logic [3:0] sample_bad,
    input logic [15:0] sample_sequence,
    input logic ingress_overrun,input wire fifth_enabled,
    output logic active,
    output logic result_valid,
    output logic [1:0] result_kind, // 0 confirmed, 1 timeout, 2 numeric exception
    output logic [2:0] result_label,
    output wire check_valid,
    output wire signed [63:0] score0,score1,score2,score3,score4,
    output wire [3:0] channel_mask,
    output wire [15:0] check_sequence_number,
    output wire numeric_fault,
    output logic [31:0] gap_count,
    output logic [1:0] confirmations,
    output wire live_update,live_match,
    output wire [2:0] live_label,
    output wire [15:0] debug_pc,
    output wire debug_raw_check,debug_rebase,debug_engine_ready,
    output wire [7:0] debug_fifo_count,
    output wire [15:0] debug_epoch,
    output wire debug_eligible
);
    localparam integer DEPTH=128;
    localparam logic [31:0] STALE_CYCLES=CLOCK_HZ*3/4;
    localparam logic [31:0] TRIAL_CYCLES=CLOCK_HZ*18;
    logic [166:0] fifo[0:DEPTH-1];
    logic [6:0] wp,rp;
    logic [7:0] count;
    logic [166:0] read_word,head;
    logic head_valid,read_pending;
    logic [15:0] epoch,last_seq;
    logic have_seq,reset_pending,stale_latched,method;
    logic [31:0] fresh_timer,trial_timer;
    wire begin_trial=start&&!active;
    wire accept=sample_valid&&sample_ready;
    wire gap=accept&&have_seq&&(sample_sequence!=(last_seq+16'd1));
    wire stale=have_seq&&!stale_latched&&(fresh_timer>=STALE_CYCLES)&&!accept;
    wire rebase=begin_trial||gap||stale||ingress_overrun;
    wire engine_ready;
    wire read_issue=!head_valid&&!read_pending&&(count!=0);
    wire consumed=head_valid&&engine_ready;
    wire [15:0] check_epoch,check_sequence;
    assign check_sequence_number=check_sequence;
    wire raw_check_valid;
    wire [15:0] check_age=last_seq-check_sequence;
    wire current_check=raw_check_valid&&active&&check_epoch==epoch&&
                       !rebase&&!stale_latched&&check_age<=16'd93;
    assign check_valid=current_check;
    assign sample_ready=count<8'(DEPTH-1);
    logic [2:0] best_label,last_label,scan_index;
    logic [31:0] best,second,decision_scores[0:4];
    logic [2:0] good_count,decision_state;
    logic eligible,score_range_ok,ratio_hi_gt,ratio_hi_eq,ratio_lo_ge,eligible_base;
    logic [31:0] ratio_source;
    logic [63:0] ratio_snapshot;
    logic [63:0] ratio_product;
    logic [15:0] decision_epoch,decision_sequence;
    wire decision_valid=decision_state==7&&active&&!rebase&&!stale_latched&&!confirmation_clear&&
                        decision_epoch==epoch&&(last_seq-decision_sequence)<=16'd93;
    // Publish each *validated decision*, not raw argmax scores. A changed
    // candidate starts a new streak. A failed window explicitly clears display.
    assign live_update=decision_valid;
    assign live_match=eligible && confirmations>=2 && best_label==last_label;
    assign live_label=best_label;
    assign debug_raw_check=raw_check_valid;
    assign debug_rebase=rebase;
    assign debug_engine_ready=engine_ready;
    assign debug_fifo_count=count;
    assign debug_epoch=epoch;
    assign debug_eligible=eligible;
    logic fault_seen;
    wire [31:0] unused_cycles;
    // Separate top-two search, ratio product and comparison into clocked steps.
    // Four scores are bounded below 16, so Q4.28 is sufficient at this boundary.
    always_ff @(posedge clk)begin
        if(!rst_n)begin
            decision_state<=0;scan_index<=0;best<=0;second<=0;best_label<=0;
            good_count<=0;eligible<=0;ratio_product<=0;ratio_source<=0;ratio_snapshot<=0;
            ratio_hi_gt<=0;ratio_hi_eq<=0;ratio_lo_ge<=0;eligible_base<=0;decision_epoch<=0;decision_sequence<=0;score_range_ok<=0;
            for(integer k=0;k<5;k=k+1)decision_scores[k]<=0;
        end else begin case(decision_state)
        0:if(current_check)begin
            decision_scores[0]<=score0[31:0];decision_scores[1]<=score1[31:0];
            decision_scores[2]<=score2[31:0];decision_scores[3]<=score3[31:0];decision_scores[4]<=fifth_enabled?score4[31:0]:32'd0;
            score_range_ok<=score0[63:32]==0&&score1[63:32]==0&&score2[63:32]==0&&score3[63:32]==0&&score4[63:32]==0;
            decision_epoch<=check_epoch;decision_sequence<=check_sequence;
            good_count<={2'd0,channel_mask[0]}+{2'd0,channel_mask[1]}+
                        {2'd0,channel_mask[2]}+{2'd0,channel_mask[3]};
            best<=0;second<=0;scan_index<=0;best_label<=0;decision_state<=1;
        end
        1:begin
            if(decision_scores[scan_index]>=best)begin
                second<=best;best<=decision_scores[scan_index];best_label<=scan_index;
            end else if(decision_scores[scan_index]>second)second<=decision_scores[scan_index];
            if(scan_index==4)decision_state<=2;else scan_index<=scan_index+1'b1;
        end
        // Keep complete operand/product registers around the DSP. Split the
        // exact unsigned 64-bit comparison so partial-product carry and the
        // comparison cannot form one DSP-to-control timing path.
        2:begin ratio_source<=second;decision_state<=3;end
        3:begin ratio_product<=ratio_source*32'd308700775;decision_state<=4;end
        4:begin ratio_snapshot<=ratio_product;decision_state<=5;end
        5:begin
            ratio_hi_gt<={4'd0,best[31:4]}>ratio_snapshot[63:32];
            ratio_hi_eq<={4'd0,best[31:4]}==ratio_snapshot[63:32];
            ratio_lo_ge<={best[3:0],28'd0}>=ratio_snapshot[31:0];
            eligible_base<=score_range_ok&&good_count>=2&&best>=32'd26843546;
            decision_state<=6;
        end
        6:begin eligible<=eligible_base&&(ratio_hi_gt||(ratio_hi_eq&&ratio_lo_ge));decision_state<=7;end
        7:decision_state<=0;
        default:decision_state<=0;
        endcase
        if(confirmation_clear)decision_state<=0;
        end
    end
    ssvep_hardware_core engine(
        .clk(clk),.rst_n(rst_n),.sample_valid(head_valid),.sample_ready(engine_ready),
        .sample0($signed(head[127:96])),.sample1($signed(head[95:64])),
        .sample2($signed(head[63:32])),.sample3($signed(head[31:0])),
        .sample_bad(head[131:128]),.sample_reset(head[132]),.sample_active(head[133]),
        .sample_method(head[134]),.sample_epoch(head[166:151]),.sample_sequence(head[150:135]),
        .check_valid(raw_check_valid),.score0(score0),.score1(score1),.score2(score2),.score3(score3),.score4(score4),
        .channel_mask(channel_mask),.check_epoch(check_epoch),.check_sequence(check_sequence),
        .numeric_fault(numeric_fault),.debug_phase(debug_pc),.cycle_counter(unused_cycles));
    always_ff @(posedge clk)begin
        if(!rst_n)begin
            wp<=0;rp<=0;count<=0;head_valid<=0;read_pending<=0;read_word<=0;head<=0;
            epoch<=0;last_seq<=0;have_seq<=0;reset_pending<=0;stale_latched<=0;method<=0;
            fresh_timer<=0;trial_timer<=0;active<=0;result_valid<=0;result_kind<=0;result_label<=0;
            gap_count<=0;confirmations<=0;last_label<=0;fault_seen<=0;
        end else begin
            result_valid<=0;
            if(fresh_timer<STALE_CYCLES)fresh_timer<=fresh_timer+1'b1;
            // Continuous recognition runs until a stop request.
            if(rebase)begin epoch<=epoch+1'b1;reset_pending<=1;confirmations<=0;end
            if(gap||ingress_overrun)gap_count<=gap_count+1'b1;
            if(stale)stale_latched<=1;
            if(begin_trial)begin active<=1;trial_timer<=0;method<=cca_method;end
            if(accept)begin
                fifo[wp]<={epoch+{15'd0,rebase},sample_sequence,
                           begin_trial?cca_method:method,begin_trial||active,
                           reset_pending||rebase,sample_bad,sample0,sample1,sample2,sample3};
                wp<=wp+1'b1;reset_pending<=0;last_seq<=sample_sequence;
                have_seq<=1;fresh_timer<=0;stale_latched<=0;
            end
            if(read_issue)begin read_word<=fifo[rp];rp<=rp+1'b1;read_pending<=1;end
            if(read_pending)begin head<=read_word;head_valid<=1;read_pending<=0;end
            if(consumed)head_valid<=0;
            case({accept,read_issue})
            2'b10:count<=count+1'b1;
            2'b01:count<=count-1'b1;
            default:;
            endcase
            if(decision_valid)begin
                if(!eligible)confirmations<=0;
                else begin
                    last_label<=best_label;
                    if(confirmations!=0&&best_label==last_label)begin
                        if(confirmations>=2)begin
                            confirmations<=3;result_valid<=1;result_kind<=0;result_label<=best_label;
                        end else confirmations<=confirmations+1'b1;
                    end else confirmations<=1;
                end
            end
            if(confirmation_clear)begin confirmations<=0;last_label<=0;end
            if(numeric_fault&&!fault_seen)begin
                fault_seen<=1;confirmations<=0;result_valid<=1;result_kind<=2;
            end
        end
    end
endmodule
