from pathlib import Path
import sys
root=Path(__file__).resolve().parents[2]
s=(root/'Sources/MomentsCache.m').read_text()
a=s.index('#define WU_COMMENT_COMPLETION(')
b=s.index('#undef WU_COMMENT_COMPLETION',a)+len('#undef WU_COMMENT_COMPLETION')
# Extract the ACTUAL production trampoline, not a hand-reimplemented test copy.
out=Path(sys.argv[1]); out.parent.mkdir(parents=True,exist_ok=True)
out.write_text(s[a:b]+'\n')
assert 'if([objc_getAssociatedObject(view,&commentCompletionDepthKey) unsignedIntegerValue]) return;' in s
assert 'if(!completionCode && snapshot.count) WUMomentsCacheObserveHost(item);' in s
print('production completion trampoline extracted')
