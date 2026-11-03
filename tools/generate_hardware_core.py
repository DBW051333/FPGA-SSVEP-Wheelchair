"""Generate a fixed FBCCA hardware task graph from named algorithm stages.

The input is this algorithm, not an instruction image. Scalar signals, tensor
banks, loop counters and dedicated operator interfaces are wired at generation.
"""
from pathlib import Path
import json
from hardware_graph import Graph

ROOT = Path(__file__).resolve().parents[1]
g = Graph()


def wait_unit(done, fault):
    g.step(jump=('WAIT', done, fault))


def filter_task(window):
    g.step('owner<=1;')
    g.step(comb=f'filter_start=1;filter_window={int(window)};')
    wait_unit('filter_done', 'filter_fault')
    g.step('owner<=0;')


def vector_task(a, b, periodic, length="16'd250", lag="7'd0"):
    g.step(f'owner<=2;vector_source_a<={a};vector_source_b<={b};vector_periodic<={int(periodic)};vector_length<={length};vector_denominator<=250;vector_lag<={lag};')
    g.step(comb='vector_start=1;')
    wait_unit('vector_done', 'vector_fault')
    g.step('owner<=0;covariance<=vector_value;')


def covariance_task(prefix, periodic):
    g.step('covariance_sum<=0;covariance_lag<=local_covariance?7\'d1:7\'d0;')
    g.label(prefix+'_LOOP')
    vector_task('`HW_XB+row_band', 'template_base' if periodic else '`HW_XB+col_band', periodic,
                "16'd250-{9'd0,covariance_lag}", 'covariance_lag')
    g.branch('!local_covariance', prefix+'_DONE')
    g.read('lag_weight', "`HW_TRI+{7'd0,covariance_lag}-14'd1")
    g.math('weighted_covariance', 0, 'covariance', 'lag_weight')
    g.add('covariance_sum', 'covariance_sum', 'weighted_covariance')
    g.branch('covariance_lag==11', prefix+'_LOCAL_DONE')
    g.step("covariance_lag<=covariance_lag+1'b1;", jump=prefix+'_LOOP')
    g.label(prefix+'_LOCAL_DONE')
    g.step('covariance<=covariance_sum;')
    g.label(prefix+'_DONE')


def stats(prefix, source, need_range):
    g.step('sum_value<=0;index<=0;')
    g.label(prefix+'_REQ')
    g.step(comb=f'ram_a={source}+{{5\'d0,index}};')
    seq="sum_value<=add_result[63:0];index<=index+1'b1;"
    if need_range:
        seq += 'if(index==0||ram_qa<range_min)range_min<=ram_qa;if(index==0||ram_qa>range_max)range_max<=ram_qa;'
    g.step(seq, comb='add_a=sum_value;add_b=ram_qa;',
           jump=('RAW', f'if(add_result[64]!=add_result[63])state<=@FAIL@;else if(index==249)state<=@{prefix}_DIV@;else state<=@{prefix}_REQ@;'))
    g.label(prefix+'_DIV')
    g.math('mean_value', 1, 'sum_value', "64'sd67108864000")


def eigen_task(vectors):
    g.step(f'owner<=4;eigen_keep_vectors<={int(vectors)};')
    g.step(comb='eigen_start=1;')
    wait_unit('eigen_done', 'eigen_fault')
    g.step('owner<=0;')


def matrix_task(which, destination):
    g.step(f'owner<=3;matrix_pass<=2\'d{which};')
    g.step(comb=f'matrix_start=1;matrix_transpose={int(which==2)};')
    wait_unit('matrix_done', 'matrix_fault')
    g.step('owner<=0;')


g.label('WAIT_SAMPLE')
g.step('''if(sample_valid)begin
 frame_active<=sample_active;frame_method<=sample_method;frame_epoch<=sample_epoch;frame_sequence<=sample_sequence;
 if(sample_reset)begin accepted_count<=0;hop_count<=0;end
 frame_good<=input_good;
 for(integer z=0;z<4;z=z+1)pre_samples[(3-z)*64+:64]<=input_good[z]?raw_input[z]:64'sd0;
end''', jump=('RAW', 'if(sample_valid)state<=@PREPROCESS@;'))
g.label('PREPROCESS')
filter_task(False)
g.step('clean_samples<=filter_result;initialized<=frame_good;channel<=0;')
g.label('STORE_CLEAN')
g.write("`HW_CLEAN+channel_ring+{5'd0,write_pointer}", '$signed(clean_samples[(3-channel)*64+:64])')
g.write("`HW_BAD+channel_ring+{5'd0,write_pointer}", "{63'd0,!frame_good[channel]}")
g.branch('channel==3', 'ADVANCE_INGRESS')
g.step("channel<=channel+1'b1;", jump='STORE_CLEAN')
g.label('ADVANCE_INGRESS')
g.step("write_pointer<=write_pointer==374?9'd0:write_pointer+1'b1;")
g.branch('!frame_active', 'INACTIVE')
g.branch('accepted_count==312', 'HOP')
g.step("accepted_count<=accepted_count+1'b1;")
g.branch('accepted_count==312', 'CLASSIFY')
g.go('WAIT_SAMPLE')
g.label('INACTIVE')
g.step('accepted_count<=0;hop_count<=0;', jump='WAIT_SAMPLE')
g.label('HOP')
g.branch('hop_count>=123', 'HOP_READY')
g.step("hop_count<=hop_count+9'd2;", jump='WAIT_SAMPLE')
g.label('HOP_READY')
g.step("hop_count<=hop_count-9'd123;", jump='CLASSIFY')

g.label('CLASSIFY')
g.step("good_mask<=0;good_count<=0;history_skip<=0;channel<=0;window_start<=write_pointer>=312?write_pointer-9'd312:write_pointer+9'd63;")
g.label('SNAPSHOT_BEGIN')
g.step('index<=0;ring_index<=window_start;bad_count[channel]<=0;history_bad[channel]<=0;')
g.label('SNAPSHOT')
g.read('sample_value', "`HW_CLEAN+channel_ring+{5'd0,ring_index}")
g.write("`HW_X+channel_window+{5'd0,index}", 'sample_value')
g.read('sample_value', "`HW_BAD+channel_ring+{5'd0,ring_index}")
g.step("if(index<62)history_bad[channel]<=history_bad[channel]+{8'd0,sample_value[0]};else bad_count[channel]<=bad_count[channel]+{8'd0,sample_value[0]};")
g.branch('index==311', 'RAW_STATISTICS')
g.step("index<=index+1'b1;ring_index<=ring_index==374?9'd0:ring_index+1'b1;", jump='SNAPSHOT')
g.label('RAW_STATISTICS')
stats('RAW', "`HW_X+channel_window+14'd62", True)
g.step('analysis_mean[channel]<=mean_value;')
g.add('peak_range', 'range_max', 'range_min', True)
vector_task("`HW_X+channel_window+14'd62", "`HW_X+channel_window+14'd62", False)
g.math('square_mean', 0, 'mean_value', 'mean_value')
g.add('variance', 'covariance', 'square_mean', True)
g.branch("bad_count[channel]!=0||variance<64'sd107374||variance>64'sd6710886400000000||peak_range>64'sd5368709120000", 'CENTER_BEGIN')
g.step("good_mask[channel]<=1;good_count<=good_count+1'b1;if(history_bad[channel]!=0)history_skip<=1;")
g.label('CENTER_BEGIN')
g.step('index<=0;')
g.label('CENTER_REQ')
g.step(comb="ram_a=`HW_X+channel_window+{5'd0,index};")
g.step('sample_value<=add_result[63:0];', comb='add_a=ram_qa;add_b=analysis_mean[channel];add_sub=1;',
       jump=('CHECK', 'add_result[64]!=add_result[63]'))
g.write("`HW_X+channel_window+{5'd0,index}", 'sample_value')
g.branch('index==311', 'CHANNEL_DONE')
g.step("index<=index+1'b1;", jump='CENTER_REQ')
g.label('CHANNEL_DONE')
g.branch('channel==3', 'QUALITY_DONE')
g.step("channel<=channel+1'b1;", jump='SNAPSHOT_BEGIN')
g.label('QUALITY_DONE')
g.branch('good_count<2', 'INVALID')
g.step('for(integer z=0;z<5;z=z+1)scores[z]<=0;band<=0;')

g.label('BAND')
filter_task(True)
g.step('channel<=0;')
g.label('BAND_MEANS')
stats('BANK', '`HW_XB+channel_band', False)
g.step('bank_mean[channel]<=mean_value;')
g.branch('channel==3', 'CXX_BEGIN')
g.step("channel<=channel+1'b1;", jump='BAND_MEANS')
g.label('CXX_BEGIN')
g.step('row<=0;col<=0;')
g.label('CXX')
g.branch('!good_mask[row]||!good_mask[col]', 'CXX_ZERO')
covariance_task('EEG_COV', False)
g.branch('local_covariance', 'CXX_STORE')
g.math('square_mean', 0, 'bank_mean[row]', 'bank_mean[col]')
g.add('covariance', 'covariance', 'square_mean', True)
g.go('CXX_STORE')
g.label('CXX_ZERO')
g.step('covariance<=0;')
g.label('CXX_STORE')
g.tensor_write("8'h00+{4'd0,row,col}",'covariance',"8'h00+{4'd0,col,row}",'covariance',"row!=col")
g.branch('col==3', 'CXX_ROW')
g.step("col<=col+1'b1;", jump='CXX')
g.label('CXX_ROW')
g.branch('row==3', 'SCALE_BEGIN')
g.step("row<=row+1'b1;col<=row+1'b1;", jump='CXX')
g.label('SCALE_BEGIN')
g.step('trace_value<=0;inner<=0;')
g.label('TRACE')
g.tensor_read('term',"8'h00+{4'd0,inner,inner}")
g.add('trace_value','trace_value','term')
g.branch('inner==3', 'SCALE')
g.step("inner<=inner+1'b1;", jump='TRACE')
g.label('SCALE')
g.math('scale_value', 1, 'trace_value', "$signed({33'd0,good_count,28'd0})")
g.step("if(scale_value<64'sd268435456)scale_value<=64'sd268435456;")
g.math('root_scale', 2, 'scale_value')
g.step('matrix_index<=0;')
g.label('NORMALIZE_CXX')
g.tensor_read('term',"8'h00+{4'd0,matrix_index}")
g.math('term',1,'term','scale_value')
g.branch('matrix_index%5!=0', 'NORMALIZE_STORE')
g.add('term', 'term', "64'sd268")
g.label('NORMALIZE_STORE')
g.tensor_write("8'h60+{4'd0,matrix_index}",'term')
g.branch('matrix_index==15', 'WHITEN_BEGIN')
g.step("matrix_index<=matrix_index+1'b1;", jump='NORMALIZE_CXX')
g.label('WHITEN_BEGIN')
eigen_task(True)
g.math('eigen_max', 1, "64'sd268435456", 'scale_value')
g.step('inner<=0;')
g.label('EIGEN_MAX')
g.tensor_read('term',"8'h60+{4'd0,inner,inner}")
g.step('if(term>eigen_max)eigen_max<=term;')
g.branch('inner==3', 'CUTOFF')
g.step("inner<=inner+1'b1;", jump='EIGEN_MAX')
g.label('CUTOFF')
g.math('cutoff', 0, 'eigen_max', "64'sd268")
g.step('inner<=0;')
g.label('INVERSE')
g.tensor_read('term',"8'h60+{4'd0,inner,inner}")
g.step('if(term<cutoff)term<=cutoff;')
g.math('term', 2, 'term')
g.math('term', 1, "64'sd268435456", 'term')
g.step('inverse[inner]<=term;')
g.branch('inner==3', 'WX_BEGIN')
g.step("inner<=inner+1'b1;", jump='INVERSE')
g.label('WX_BEGIN')
g.step('row<=0;col<=0;')
g.label('WX_CELL')
g.step('inner<=0;whiten_sum<=0;')
g.label('WX_TERM')
g.step(comb="tensor_a=8'h70+{4'd0,row,inner};tensor_b=8'h70+{4'd0,col,inner};")
g.math('term',0,'tensor_qa','tensor_qb')
g.math('term_scaled', 0, 'term', 'inverse[inner]')
g.add('whiten_sum', 'whiten_sum', 'term_scaled')
g.branch('inner==3', 'WX_STORE')
g.step("inner<=inner+1'b1;", jump='WX_TERM')
g.label('WX_STORE')
g.tensor_write("8'h20+{4'd0,row,col}",'whiten_sum',"8'h20+{4'd0,col,row}",'whiten_sum',"row!=col")
g.branch('col==3', 'WX_ROW')
g.step("col<=col+1'b1;", jump='WX_CELL')
g.label('WX_ROW')
g.branch('row==3', 'TARGET_BEGIN')
g.step("row<=row+1'b1;col<=row+1'b1;", jump='WX_CELL')
g.label('TARGET_BEGIN')
g.step('target<=0;')
g.label('TARGET')
g.step('row<=0;col<=0;')
g.label('CXY')
g.branch('!good_mask[row]', 'CXY_ZERO')
covariance_task('REFERENCE_COV', True)
g.go('CXY_STORE')
g.label('CXY_ZERO')
g.step('covariance<=0;')
g.label('CXY_STORE')
g.tensor_write("8'h10+{4'd0,row,col}",'covariance')
g.branch('col==3', 'CXY_ROW')
g.step("col<=col+1'b1;", jump='CXY')
g.label('CXY_ROW')
g.branch('row==3', 'WY_BEGIN')
g.step("row<=row+1'b1;col<=0;", jump='CXY')
g.label('WY_BEGIN')
g.step('matrix_index<=0;')
g.label('WY_LOAD')
g.read('term', "`HW_YWHITEN+(local_covariance?14'd80:14'd0)+{7'd0,target,4'd0}+{10'd0,matrix_index}")
g.tensor_write("8'h30+{4'd0,matrix_index}",'term')
g.branch('matrix_index==15', 'WHITEN_CXY')
g.step("matrix_index<=matrix_index+1'b1;", jump='WY_LOAD')
g.label('WHITEN_CXY')
matrix_task(0, 'transformed')
g.step('matrix_index<=0;')
g.label('SCALE_T')
g.tensor_read('term',"8'h40+{4'd0,matrix_index}")
g.math('term',1,'term','root_scale')
g.tensor_write("8'h40+{4'd0,matrix_index}",'term')
g.branch('matrix_index==15', 'FORM_M')
g.step("matrix_index<=matrix_index+1'b1;", jump='SCALE_T')
g.label('FORM_M')
matrix_task(1, 'mixed')
matrix_task(2, 'tensor')
eigen_task(False)
g.step('inner<=0;candidate_max<=0;')
g.label('CANDIDATE_MAX')
g.tensor_read('term',"8'h60+{4'd0,inner,inner}")
g.step('if(term>candidate_max)candidate_max<=term;')
g.branch('inner==3', 'WEIGHT')
g.step("inner<=inner+1'b1;", jump='CANDIDATE_MAX')
g.label('WEIGHT')
g.step("if(candidate_max>64'sd268435456)candidate_max<=64'sd268435456;")
g.read('band_weight', "`HW_WEIGHTS+(frame_method?14'd5:14'd0)+{11'd0,band}")
g.math('weighted_score', 0, 'candidate_max', 'band_weight')
g.add('scores[target]', 'scores[target]', 'weighted_score')
g.branch('target==4', 'NEXT_BAND')
g.step("target<=target+1'b1;", jump='TARGET')
g.label('NEXT_BAND')
g.branch('band==4', 'EMIT')
g.step("band<=band+1'b1;", jump='BAND')
g.label('EMIT')
g.step('score0<=scores[0];score1<=scores[1];score2<=scores[2];score3<=scores[3];score4<=scores[4];channel_mask<=good_mask;check_epoch<=frame_epoch;check_sequence<=frame_sequence;check_valid<=1;', jump='WAIT_SAMPLE')
g.label('INVALID')
g.step('score0<=0;score1<=0;score2<=0;score3<=0;score4<=0;channel_mask<=good_mask;check_epoch<=frame_epoch;check_sequence<=frame_sequence;check_valid<=1;', jump='WAIT_SAMPLE')
g.label('FAIL')
g.step('owner<=0;numeric_fault<=1;accepted_count<=0;hop_count<=0;initialized<=0;', jump='INVALID')

defaults = '''ram_a=0;ram_b=0;ram_we=0;ram_wd=0;
filter_start=0;filter_window=0;vector_start=0;matrix_start=0;matrix_transpose=0;eigen_start=0;
math_request=0;math_kind=0;math_a=0;math_b=0;add_a=0;add_b=0;add_sub=0;
tensor_a=0;tensor_b=0;tensor_wea=0;tensor_web=0;tensor_da=0;tensor_db=0;'''
reset = '''owner<=0;write_pointer<=0;accepted_count<=0;hop_count<=0;initialized<=0;frame_good<=0;good_mask<=0;
frame_active<=0;frame_method<=0;frame_epoch<=0;frame_sequence<=0;history_skip<=0;good_count<=0;
channel<=0;row<=0;col<=0;inner<=0;index<=0;matrix_index<=0;band<=0;target<=0;covariance_lag<=0;
check_valid<=0;numeric_fault<=0;score0<=0;score1<=0;score2<=0;score3<=0;score4<=0;channel_mask<=0;
check_epoch<=0;check_sequence<=0;cycle_counter<=0;
vector_source_a<=0;vector_source_b<=0;vector_periodic<=0;vector_length<=0;vector_denominator<=250;vector_lag<=0;
matrix_pass<=0;eigen_keep_vectors<=0;'''
header = (ROOT/'tools/hardware_core_header.txt').read_text()
rtl = header + g.render('WAIT_SAMPLE', reset, defaults,
                       sequential_default='check_valid<=0;if(state!=H0)cycle_counter<=cycle_counter+1\'b1;')
rtl += 'assign sample_ready=state==H0;\nassign debug_phase=state;\nendmodule\n'
import sys
phase_text=json.dumps(g.labels,indent=2)
if '--check' in sys.argv:
    assert (ROOT/'src/ssvep_hardware_core.sv').read_text()==rtl, 'Stale fixed hardware graph'
    assert (ROOT/'assets/hardware_phases.json').read_text()==phase_text, 'Stale hardware phase map'
else:
    (ROOT/'src/ssvep_hardware_core.sv').write_text(rtl)
    (ROOT/'assets/hardware_phases.json').write_text(phase_text)
print('SSVEP DEDICATED GRAPH', len(g.nodes), 'states; named tensor banks, five dedicated operators, no ISA')
