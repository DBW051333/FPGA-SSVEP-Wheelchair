"""Emit fixed RTL control graphs. This is an offline HDL authoring helper.

No instructions, instruction storage, register indices or interpreter are emitted.
Each graph operation names its physical signals and fixed successor states.
"""
class Graph:
    def __init__(self):
        self.nodes = []
        self.labels = {}

    def label(self, name):
        assert name not in self.labels
        self.labels[name] = len(self.nodes)

    def step(self, seq='', comb='', jump=None):
        self.nodes.append(dict(seq=seq, comb=comb, jump=jump))

    def go(self, name):
        self.step(jump=name)

    def branch(self, condition, yes):
        self.step(jump=(condition, yes))

    def read(self, dst, address, port='a'):
        self.step(comb=f'ram_{port}={address};')
        self.step(f'{dst}<=ram_q{port};')

    def write(self, address, value):
        self.step(comb=f'ram_a={address};ram_we=1;ram_wd={value};')

    def tensor_read(self, dst, address, second=None, address_b="8'd0"):
        self.step(comb=f'tensor_a={address};tensor_b={address_b};')
        self.step(f'{dst}<=tensor_qa;' + (f'{second}<=tensor_qb;' if second else ''))

    def tensor_write(self, address, value, address_b=None, value_b=None, enable_b="1'b1"):
        comb=f'tensor_a={address};tensor_wea=1;tensor_da={value};'
        if address_b is not None:
            comb+=f'tensor_b={address_b};tensor_web={enable_b};tensor_db={value_b};'
        self.step(comb=comb)

    def math(self, dst, kind, a, b="64'sd0"):
        self.step(comb=f'math_request=1;math_kind=2\'d{kind};math_a={a};math_b={b};')
        self.step(f'if(math_response)begin {dst}<=math_value;end',
                  jump=('WAIT', 'math_response', 'math_error'))

    def add(self, dst, a, b, subtract=False):
        self.step(f'{dst}<=add_result[63:0];',
                  comb=f'add_a={a};add_b={b};add_sub={int(subtract)};',
                  jump=('CHECK', 'add_result[64]!=add_result[63]'))

    def render(self, initial, reset, defaults, fail='FAIL', sequential_default=''):
        def state(label):
            return 'H' + str(self.labels[label]) if isinstance(label, str) else 'H' + str(label)
        count = len(self.nodes)
        text = f'localparam integer HARDWARE_STATES={count};\n'
        text += 'typedef enum logic [15:0] {' + ','.join('H'+str(i) for i in range(count)) + '} state_t;\nstate_t state;\n'
        text += 'always_comb begin\n' + defaults + '\ncase(state)\n'
        for i, node in enumerate(self.nodes):
            if node['comb']:
                text += f'H{i}:begin {node["comb"]} end\n'
        text += 'default:;\nendcase\nend\n'
        text += f'always_ff @(posedge clk)begin\nif(!rst_n)begin state<={state(initial)};\n{reset}\nend else begin\n{sequential_default}\ncase(state)\n'
        for i, node in enumerate(self.nodes):
            nxt = 'H'+str(i+1) if i+1<count else state(initial)
            jump = node['jump']
            if jump is None:
                transition = 'state<='+nxt+';'
            elif isinstance(jump, str):
                transition = 'state<='+state(jump)+';'
            elif jump[0] == 'WAIT':
                _, valid, error = jump
                transition = f'if({valid})begin if({error})state<={state(fail)};else state<={nxt};end'
            elif jump[0] == 'CHECK':
                transition = f'if({jump[1]})state<={state(fail)};else state<={nxt};'
            elif jump[0] == 'RAW':
                transition = jump[1].replace('@NEXT@', nxt).replace('@FAIL@', state(fail))
                for label, position in self.labels.items():
                    transition = transition.replace('@'+label+'@', 'H'+str(position))
            else:
                transition = f'if({jump[0]})state<={state(jump[1])};else state<={nxt};'
            text += f'H{i}:begin {node["seq"]}\n{transition} end\n'
        text += f'default:state<={state(fail)};\nendcase\nend\nend\n'
        return text
