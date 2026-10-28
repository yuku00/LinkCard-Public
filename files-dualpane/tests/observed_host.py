"""Replay every anonymized captured equation through unmodified production style functions."""
from pathlib import Path
import json,subprocess,sys,tempfile
r=Path(__file__).resolve().parents[1]
f=json.loads((r/'tests/observed_layout.json').read_text())
assert len(f['objects'])==32 and len(f['equations'])==119
out=Path(sys.argv[1])
subprocess.run([sys.executable,str(r/'tests/style_host.py'),str(out)]+sys.argv[2:],check=True)
s=out.read_text()
# Add cases before main, preserving all production code and existing fixtures.
g=['static NativeFixture *Observed(NSMutableDictionary **objects, NSMutableArray **equations) {',
'NativeFixture *f=[NativeFixture new]; f.cell=NewCell(NSClassFromString(@"Files.DOCItemCollectionListCell"));',
'MutableObservedPlaceholder']
g[-1]='NSMutableDictionary *o=[NSMutableDictionary new]; NSMutableArray *cs=[NSMutableArray new]; o[@1]=f.cell; o[@2]=f.cell.contentView; o[@12]=f.cell.superview;'
for v in f['objects']:
 i=v['id']
 if i in (1,2,12): continue
 if v['detail']=='guide':
  if v.get('role')=='layoutMargins': g.append(f'o[@{i}]=[(UIView *)o[@{v["owner"]}] layoutMarginsGuide];')
  elif v.get('role')=='safeArea': g.append(f'o[@{i}]=[(UIView *)o[@{v["owner"]}] safeAreaLayoutGuide];')
  else: g.append(f'o[@{i}]=[UILayoutGuide new]; [(UILayoutGuide *)o[@{i}] setOwningView:o[@{v["owner"]}]];')
 else:
  cls='UIStackView' if i in (4,5) else 'UILabel' if i in (3,6,7,8,20) else 'UIView'
  expr='[NSClassFromString(@"DOCThumbnailFittingImageView") new]' if i==9 else '[NSClassFromString(@"DOCChainedTagsView") new]' if i==19 else f'[{cls} new]'
  g.append(f'o[@{i}]={expr};')
for v in f['objects']:
 i=v['id']
 if v['detail']!='view': continue
 g.append(f'{{ UIView *v=o[@{i}]; v.bounds=CGRectMake('+','.join(map(str,v['bounds']))+');')
 g.append(f'v.hidden={"YES" if v["hidden"] else "NO"}; v.translatesAutoresizingMaskIntoConstraints={"YES" if v["translatesAutoresizingMaskIntoConstraints"] else "NO"};')
 g.append('v.directionalLayoutMargins=(NSDirectionalEdgeInsets){'+','.join(map(str,v['margins']))+'};')
 if i not in (1,2,12): g.append(f'[(UIView *)o[@{v["super"]}] addSubview:v];')
 if i in (3,6,7,8,20): g.append('[(UILabel *)v setText:@"anonymous fixture"];')
 g.append('}')
for v in f['objects']:
 if 'stack' not in v: continue
 st=v['stack']; i=v['id']
 g.append(f'{{ UIStackView *s=o[@{i}]; s.axis={st["axis"]}; s.alignment={st["alignment"]}; s.spacing={st["spacing"]}; s.distribution={st["distribution"]};')
 for a in st['arranged']: g.append(f'[s addArrangedSubview:o[@{a["view"]}]]; [s setCustomSpacing:{a["customSpacingAfter"]} afterView:o[@{a["view"]}]];')
 g.append('}')
for row in f['equations']:
 owner,a,aa,rel,b,ba,m,k,pri=row
 g.append('{ NSLayoutConstraint *c=[NSLayoutConstraint constraintWithItem:o[@%d] attribute:%d relatedBy:%d toItem:%s attribute:%d multiplier:%.17g constant:%.17g]; c.priority=%.17g; [[(UIView *)o[@%d] constraints] addObject:c]; c.active=YES; [cs addObject:c]; }'%(a,aa,rel,f'o[@{b}]' if b else 'nil',ba,m,k,pri,owner))
g += ['f.row=o[@5]; f.slot=o[@10]; f.image=o[@9]; f.title=o[@3]; f.detail=o[@6];',
'f.cell.titleLabel=f.title; f.cell.subtitleLabel=f.detail; f.cell.dateLabel=o[@7]; f.cell.sizeLabel=o[@8]; f.cell.thumbnailView=f.image; f.cell.cellContent=[NSObject new];',
'f.cell.accessories=@[[UICellAccessory new]]; f.image.image=[NSObject new]; *objects=o; *equations=cs; return f;','}']
s=s.replace('int main(void)', '\n'.join(g)+'\n'+(r/'tests/style_observed_cases.inc').read_text()+'\nint main(void)')
s=s.replace('RegisterHostClasses(); PublicCases();','RegisterHostClasses(); NamedClass(@"DOCChainedTagsView",UIView.class); ObservedCases(); PublicCases();')
out.write_text(s)
