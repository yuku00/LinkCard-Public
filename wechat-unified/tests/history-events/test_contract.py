"""Portable source-contract checks only; NOT Objective-C execution/host acceptance."""
from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[2]
STATS=(ROOT/'Sources/WUStats.m').read_text()
MESSAGES=(ROOT/'Sources/Messages.m').read_text()
CACHE=(ROOT/'Sources/MomentsCache.m').read_text()
LOGIC=(ROOT/'Sources/MomentsCacheLogic.m').read_text()
class SourceContract(unittest.TestCase):
    def test_production_binding_and_overview(self):
        for s in ['binding.scanAppMessages=YES','binding.appEncoding=WUStatsAppMethodEncoding(mgr)', 'child.scanAppMessages=base.scanAppMessages','WUStatsDecodeHostPage(page,0,account,target,YES)']:
            self.assertIn(s,MESSAGES)
    def test_exact_runtime_and_shared_budget(self):
        for s in ['method_getTypeEncoding(m)','NSInvocation *call','uint32_t v=','int32_t v=','uint64_t v=','int64_t v=','[encoding isEqual:b.appEncoding]','self.pages>=self.binding.pageLimit','self.readCount>=20000']:
            self.assertIn(s,STATS)
        self.assertNotIn('self.pages=0',STATS)
        self.assertNotIn('self.readCount=0',STATS)
    def test_phase_cursor_contract(self):
        for s in ['self.phasePages=0','self.accumulator.interactionPhase++','[self.cursors removeAllObjects]','self.cursor=@{@"id":@0,@"time":@0}', 'self.appPhase?newTime<oldTime', 'page.count==0 && (app || left==0)']:
            self.assertIn(s,STATS)
        self.assertNotIn('page.count<200',STATS)
    def test_payment_has_no_text_heuristic(self):
        code=STATS.split('static NSString *WUStatsAppType(',1)[1].split('NSDictionary *WUStatsDecodeHostPage',1)[0]
        for forbidden in ['m_nsContent','containsString:','parseWCPayInfoItemIfNeed','transactionID']:
            self.assertNotIn(forbidden,code)
        self.assertIn('if(red && transfer) return @"appUnknown"',code)
    def test_completion_forwards_then_refreshes_and_never_claims_delete(self):
        code=CACHE.split('#define WU_COMMENT_COMPLETION(',1)[1].split('#undef WU_COMMENT_COMPLETION',1)[0]
        self.assertLess(code.index('@try { ((void(*)(id,SEL,TYPE,id,id))commentDeleteFinished)'),code.index('if(ret==0'))
        self.assertIn('@finally',code)
        self.assertIn('ret==0 && depth==0',code)
        self.assertIn('if(!completionCode && snapshot.count) WUMomentsCacheObserveHost(item);',CACHE)
        self.assertIn('if(ret!=0) return NO;',LOGIC)
        self.assertNotIn('@"deleted"',LOGIC)
        self.assertIn('创建/删除时间未知',LOGIC)
    def test_existing_test_suites_retained_and_new_suites_wired(self):
        runner=(ROOT/'tools/test_stats.sh').read_text()
        for name in ['WUStatsTests.m','WUStatsCompletionTests.m','WUStatsHistoryTests.m']:
            self.assertIn(name,runner)
        self.assertIn('tests/host_data.m',(ROOT/'tools/test_host_data.sh').read_text())
        self.assertIn('tests/history-events/comment_history.m',(ROOT/'tools/test_host_data.sh').read_text())
if __name__=='__main__': unittest.main(verbosity=2)
