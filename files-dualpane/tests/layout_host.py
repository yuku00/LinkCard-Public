"""Execute the unchanged production graph/schema against Foundation doubles; NOT a device width fix test."""
from pathlib import Path
import subprocess,sys,tempfile
r=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory() as d:
    output=Path(d)/'style.m'
    subprocess.run([sys.executable,str(r/'tests/style_host.py'),str(output)],check=True)
    s=output.read_text()
s=s.replace('@interface UILayoutGuide : NSObject','@interface UILayoutGuide : NSObject\n@property CGRect layoutFrame;')
s=s.replace('@interface UIView : UIResponder','''@interface UIView : UIResponder
@property CGRect frame;
@property CGSize intrinsicContentSize;
@property CGFloat alpha;
@property BOOL preservesSuperviewLayoutMargins;
@property NSArray *layoutGuides;
@property id window;
- (CGRect)convertRect:(CGRect)rect toView:(UIView *)view;
- (float)contentHuggingPriorityForAxis:(NSInteger)axis;
- (float)contentCompressionResistancePriorityForAxis:(NSInteger)axis;''')
s=s.replace('@implementation UIView\n','''@implementation UIView
- (CGRect)convertRect:(CGRect)rect toView:(UIView *)view { return rect; }
- (float)contentHuggingPriorityForAxis:(NSInteger)axis { return 250; }
- (float)contentCompressionResistancePriorityForAxis:(NSInteger)axis { return 750; }
''')
s=s.replace('@interface NSLayoutConstraint : NSObject','@interface NSLayoutConstraint : NSObject\n@property NSString *identifier;')
s=s.replace('@interface UILabel : UIView','''@interface UILabel : UIView
@property NSAttributedString *attributedText;
@property BOOL adjustsFontSizeToFitWidth;
@property CGFloat minimumScaleFactor;''')
s=s.replace('@interface UIListContentConfiguration : NSObject <NSCopying>','@interface UIListContentConfiguration : NSObject <NSCopying>\n@property NSAttributedString *attributedText;')
production=(r/'LayoutSnapshot.inc').read_text().split('@interface FPLayoutReport')[0]
production=production.replace('static NSString *FPLayoutLastReport;','').replace('static BOOL FPLayoutBusy;','')
cases=(r/'tests/layout_snapshot_cases.inc').read_text()
s=s.replace('int main(void)',production+'\n'+cases+'\nint main(void)')
s=s.replace('PublicCases(); DocumentCases(); NativeCases(); TrailingCases(); WidthReadyCases();','PublicCases(); DocumentCases(); NativeCases(); TrailingCases(); WidthReadyCases(); SnapshotCases();')
Path(sys.argv[1]).write_text(s)
