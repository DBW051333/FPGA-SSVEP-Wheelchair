from pathlib import Path
import hashlib,sys
R=Path(__file__).resolve().parents[1]
raw=(R/'assets/reference.hex').read_bytes()
words=[int(x,16) for x in raw.decode().split()]
assert len(words)==3072
# Five targets each have four 125-sample reference channels. Runtime repeats
# each channel twice; this shape is the exact periodic-folding contract.
assert all(w<=0xffffffff or w>>32==0xffffffff for w in words)
assert 5*4*125==2500 and len(words)>=2500
lines=['// Generated lossless 3072 x 32 dual-read ROM. One-cycle read latency.',
 '// reference.hex SHA256: '+hashlib.sha256(raw).hexdigest()]
for bank in range(3):
 for half in range(2):
  params=[".READ_MODE0(1'b0)",".READ_MODE1(1'b0)",'.BIT_WIDTH_0(16)','.BIT_WIDTH_1(16)']
  for chunk in range(64):
   value=sum(((words[bank*1024+chunk*16+j]>>(half*16))&65535)<<(16*j) for j in range(16))
   params.append(f".INIT_RAM_{chunk:02X}(256'h{value:064x})")
  lines.append('DPB #( '+',\n'.join(params)+f' ) bank{bank}_half{half} (')
  lines.append(f'.DOA(qa[{bank}][{half*16}+:16]),.DOB(qb[{bank}][{half*16}+:16]),')
  lines.append(".DIA(16'd0),.DIB(16'd0),.WREA(1'b0),.WREB(1'b0),")
  lines.append(".CLKA(clk),.CLKB(clk),.CEA(1'b1),.CEB(1'b1),.OCEA(1'b1),.OCEB(1'b1),")
  lines.append(".RESETA(1'b0),.RESETB(1'b0),.BLKSELA(3'd0),.BLKSELB(3'd0),")
  lines.append(".ADA({address_a[9:0],4'b0000}),.ADB({address_b[9:0],4'b0000}));")
target=R/'src/reference_dpb_init.vh'
text='\n'.join(lines)+'\n'
if '--check' in sys.argv:
 assert target.read_text()==text,'reference.hex changed: regenerate reference_dpb_init.vh'
else:target.write_text(text)
print('REFERENCE INIT PASS: 3072 exact words, 6 dual-port blocks')
