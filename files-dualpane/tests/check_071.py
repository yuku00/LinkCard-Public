from pathlib import Path
r=Path(__file__).resolve().parents[1]
s=(r/'DualPane.m').read_text(); a=(r/'NativeActions.inc').read_text()
i=(r/'CompactImages.inc').read_text(); c=(r/'CompactCells.inc').read_text()
v=(r/'CompactSelection.inc').read_text(); x=(r/'CrossPane.inc').read_text()
assert 'Version: 0.7.1' in (r/'control').read_text()
for forbidden in ('UISegmentedControl','selectedSegmentIndex','changeMode','applyMode','self.toolbarItems=','左栏 ⇄ / 首页','右栏 ⇄ / 首页'):
    assert forbidden not in s,forbidden
assert 'self.navigationItem.leftBarButtonItem=left; self.navigationItem.rightBarButtonItem=right' in s
assert 'menu:FPPaneMenu(self,0)' in s and 'menu:FPPaneMenu(self,1)' in s
assert 'self.navigationItem.titleView=close' in s and '@selector(close)' in s
assert 'setToolbarHidden:YES' in s and 'UIStackViewDistributionFillEqually' in s
assert 'self.status.numberOfLines=1' in s and 'constraintEqualToConstant:0' in s
assert 'self.status.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor' in s
assert 'message:self.status.text' in s and 'container.status.hidden=!message.length' in x
assert 'container.panes[index]' in x and 'container.panes[1-index]' in x
assert 'DOCThumbnailFittingImageView' in i and 'UIImageView.class' not in i
assert 'stack.arrangedSubviews containsObject:v' in i and 'NSLayoutAttributeWidth' in i
assert 'constraintEqualToConstant:20' in i and 'setCustomSpacing:6 afterView:slot' in i
assert i.index('c.active=NO;') < i.index('active=[pair[1] boolValue]')
assert 'reservedLayoutSize=CGSizeMake(20,20)' in c and 'reservedLayoutSize=original.imageProperties.reservedLayoutSize' in c
assert 'if(arranged)' in c and 'FPNameLines(available,font.lineHeight)' in c
assert 'UICellAccessoryMultiselect.class' in v and 'list.accessories=filtered' in v
assert 'highlight.hidden=!cell.isSelected' in v and 'FPSelectionTraits(cell.accessibilityTraits,cell.isSelected)' in v
assert 'UIAccessibilityTraitSelected' in v and 'UIUserInterfaceStyleDark ? 0.28 : 0.16' in v
assert '[highlight removeFromSuperview]' in v and 'isEqual:filtered' in v
assert 'StyleCell(v,NO); ((void(*)(id,SEL))ro)(v,reuse)' in a
assert '((void(*)(id,SEL,BOOL))so)(v,selected,value)' in a
assert 'if(hadStyle && !IsPaneListCell(v)) StyleCell(v,NO)' in a
for forbidden in ('allowsMultipleSelection=NO','selectItemAtIndexPath:','deselectItemAtIndexPath:','valueForKey:','ivar_getOffset','object_getIvar','layoutIfNeeded','setNeedsLayout]; ['):
    assert forbidden not in i+c+v+a,forbidden
assert 'InExperiment(collection.delegate)' in c and 'PaneForResponder(cell)' in c
print('PASS 0.7.1: header pane bindings/center close, no segmented/bottom toolbar, collapsed single-line status/full result, thumbnail slot and reserved image width, exact multiselect filter, native selected mapping and restoration')
print('LIMIT static structure checks are not UIKit rendering. CI host fixture executes production visual functions with public-view doubles.')
