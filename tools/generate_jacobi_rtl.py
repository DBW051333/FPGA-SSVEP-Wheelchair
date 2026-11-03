from pathlib import Path
from hardware_graph import Graph

ROOT = Path(__file__).resolve().parents[1]
g = Graph()
g.label('IDLE')
g.step(jump=('RAW', 'if(start)state<=@LOAD@;'))
g.label('LOAD')
g.step("keep_vectors<=with_vectors;fault<=0;sweep<=0;p<=0;q<=1;matrix_index<=0;")
g.branch('!keep_vectors','PAIR')
g.label('INITIALIZE_V')
g.tensor_write("8'h70+{4'd0,matrix_index}","matrix_index[3:2]==matrix_index[1:0]?64'sd268435456:64'sd0")
g.branch('matrix_index==15','PAIR')
g.step("matrix_index<=matrix_index+1'b1;",jump='INITIALIZE_V')
g.label('PAIR')
g.tensor_read('apq',"8'h60+{4'd0,p,q}")
g.add('negated', "64'sd0", 'apq', True)
g.step('magnitude<=apq>negated?apq:negated;')
g.branch("magnitude<64'sd1", 'NEXT_PAIR')
g.tensor_read('diag_p',"8'h60+{4'd0,p,p}",'diag_q',"8'h60+{4'd0,q,q}")
g.add('delta','diag_q','diag_p',True)
g.math('twice', 0, 'apq', "64'sd536870912")
g.add('negative_delta', "64'sd0", 'delta', True)
g.add('negative_twice', "64'sd0", 'twice', True)
g.step('scale_d<=delta>negative_delta?delta:negative_delta;scale_a<=twice>negative_twice?twice:negative_twice;')
g.step('scale<=scale_d>scale_a?scale_d:scale_a;')
g.math('nd', 1, 'delta', 'scale')
g.math('na', 1, 'twice', 'scale')
g.math('dsq', 0, 'nd', 'nd')
g.math('asq', 0, 'na', 'na')
g.add('norm', 'dsq', 'asq')
g.math('norm', 2, 'norm')
g.branch('nd>=0', 'POSITIVE_NORM')
g.add('norm', "64'sd0", 'norm', True)
g.label('POSITIVE_NORM')
g.add('norm', 'norm', 'nd')
g.math('tangent', 1, 'na', 'norm')
g.math('t_sq', 0, 'tangent', 'tangent')
g.add('t_sq', 't_sq', "64'sd268435456")
g.math('norm', 2, 't_sq')
g.math('cosine', 1, "64'sd268435456", 'norm')
g.math('sine', 0, 'tangent', 'cosine')
g.math('shift', 0, 'tangent', 'apq')
g.add('diag_p','diag_p','shift',True)
g.add('diag_q','diag_q','shift')
g.tensor_write("8'h60+{4'd0,p,p}",'diag_p',"8'h60+{4'd0,q,q}",'diag_q')
g.tensor_write("8'h60+{4'd0,p,q}","64'd0","8'h60+{4'd0,q,p}","64'd0")
g.step('row<=0;rot_vectors<=0;')
g.label('ROWS')
g.branch('!rot_vectors&&(row==p||row==q)', 'ROW_NEXT')
g.tensor_read('ax',"(rot_vectors?8'h70:8'h60)+{4'd0,row,p}",'ay',"(rot_vectors?8'h70:8'h60)+{4'd0,row,q}")
g.step('rot_issue<=0;rot_received<=0;')
g.label('ROT_ISSUE')
g.step('rot_issue<=rot_issue+1\'b1;',
       comb="math_request=1;math_kind=0;math_a=(rot_issue==0||rot_issue==3)?cosine:sine;math_b=(rot_issue==0||rot_issue==2)?ax:ay;",
       jump=('RAW', 'if(rot_issue==3)state<=@ROT_DRAIN@;else state<=@ROT_ISSUE@;'))
g.label('ROT_DRAIN')
g.step("if(math_response)begin rot_product[rot_received]<=math_value;rot_received<=rot_received+1'b1;end",
       jump=('RAW', 'if(math_response)begin if(math_error)state<=@FAIL@;else if(rot_received==3)state<=@NEXT@;end'))
g.add('new_x', 'rot_product[0]', 'rot_product[1]', True)
g.add('new_y', 'rot_product[2]', 'rot_product[3]')
g.tensor_write("(rot_vectors?8'h70:8'h60)+{4'd0,row,p}",'new_x',"(rot_vectors?8'h70:8'h60)+{4'd0,row,q}",'new_y')
g.branch('rot_vectors','ROW_NEXT')
g.tensor_write("8'h60+{4'd0,p,row}",'new_x',"8'h60+{4'd0,q,row}",'new_y')
g.label('ROW_NEXT')
g.branch('row==3', 'ROWS_DONE')
g.step("row<=row+1'b1;", jump='ROWS')
g.label('ROWS_DONE')
g.branch('rot_vectors||!keep_vectors', 'NEXT_PAIR')
g.step('row<=0;rot_vectors<=1;', jump='ROWS')
g.label('NEXT_PAIR')
g.branch('q==3', 'NEXT_P')
g.step("q<=q+1'b1;", jump='PAIR')
g.label('NEXT_P')
g.branch('p==2', 'NEXT_SWEEP')
g.step("p<=p+1'b1;q<=p+2'd2;", jump='PAIR')
g.label('NEXT_SWEEP')
g.branch('sweep==11', 'CHECK_BEGIN')
g.step("sweep<=sweep+1'b1;p<=0;q<=1;", jump='PAIR')
g.label('CHECK_BEGIN')
g.step('p<=0;q<=1;')
g.label('CHECK')
g.tensor_read('apq',"8'h60+{4'd0,p,q}")
g.add('negated', "64'sd0", 'apq', True)
g.step('magnitude<=apq>negated?apq:negated;')
g.branch("magnitude>64'sd134", 'FAIL')
g.branch('q==3', 'CHECK_P')
g.step("q<=q+1'b1;", jump='CHECK')
g.label('CHECK_P')
g.branch('p==2', 'DONE')
g.step("p<=p+1'b1;q<=p+2'd2;", jump='CHECK')
g.label('DONE')
g.step('done<=1;', jump='IDLE')
g.label('FAIL')
g.step('fault<=1;done<=1;', jump='IDLE')

header = '''// Dedicated 4x4, twelve-sweep Jacobi tensor hardware.
// Matrix registers and p/q/row/sweep counters are algorithm-specific state.
module ssvep_jacobi(input wire clk,rst_n,start,with_vectors,
 output logic done,fault,
 output logic [7:0] tensor_a,tensor_b,output logic tensor_wea,tensor_web,
 output logic signed [63:0] tensor_da,tensor_db,input wire signed [63:0] tensor_qa,tensor_qb,
 output logic math_request,output logic [1:0] math_kind,
 output logic signed [63:0] math_a,math_b,
 input wire math_response,math_error,input wire signed [63:0] math_value);
 logic signed [63:0] diag_p,diag_q;logic [3:0] matrix_index;
 logic keep_vectors,rot_vectors;
 logic [1:0] p,q,row;
 logic [3:0] sweep;
 logic [2:0] rot_issue,rot_received;
 logic signed [63:0] apq,negated,magnitude,delta,twice,negative_delta,negative_twice;
 logic signed [63:0] scale_d,scale_a,scale,nd,na,dsq,asq,norm,tangent,t_sq,cosine,sine,shift;
 logic signed [63:0] ax,ay,new_x,new_y,rot_product[0:3];
 logic signed [63:0] add_a,add_b;logic add_sub;
 wire signed [64:0] add_result=add_sub?({add_a[63],add_a}-{add_b[63],add_b}):({add_a[63],add_a}+{add_b[63],add_b});
'''
rtl = header + g.render('IDLE', 'done<=0;fault<=0;keep_vectors<=0;rot_vectors<=0;p<=0;q<=1;row<=0;sweep<=0;rot_issue<=0;rot_received<=0;',
                       "math_request=0;math_kind=0;math_a=0;math_b=0;add_a=0;add_b=0;add_sub=0;tensor_a=0;tensor_b=0;tensor_wea=0;tensor_web=0;tensor_da=0;tensor_db=0;",
                       sequential_default='done<=0;') + 'endmodule\n'
import sys
if '--check' in sys.argv:
    assert (ROOT/'src/ssvep_jacobi.sv').read_text()==rtl, 'Stale Jacobi RTL'
else:
    (ROOT/'src/ssvep_jacobi.sv').write_text(rtl)
print('JACOBI HARDWARE GRAPH', len(g.nodes), 'states; no instruction decoder')
