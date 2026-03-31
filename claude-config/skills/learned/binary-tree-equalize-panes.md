# Binary Tree Layout Equalization by Leaf Count

**Extracted:** 2026-03-30
**Context:** Split-pane layout systems using binary trees (terminals, editors, panels)

## Problem
Setting all split ratios to 0.5 in a binary tree doesn't produce equal-sized panes. Sequential splits create right-heavy trees where the first pane gets 50%, the second 25%, the third 12.5%, etc.

```
Split(0.5) → [Leaf1, Split(0.5) → [Leaf2, Split(0.5) → [Leaf3, Leaf4]]]
Result: 50% / 25% / 12.5% / 12.5%  ← NOT EQUAL
```

## Solution
Count leaves in each subtree and set the ratio proportionally:

```typescript
private resetRatios(node: LayoutNode): LayoutNode {
  if (node.type === 'leaf') return node;

  const leftCount = this.countLeaves(node.children[0]);
  const rightCount = this.countLeaves(node.children[1]);
  const total = leftCount + rightCount;
  const ratio = total > 0 ? leftCount / total : 0.5;

  return {
    ...node,
    ratio,
    children: [this.resetRatios(node.children[0]), this.resetRatios(node.children[1])],
  };
}

private countLeaves(node: LayoutNode): number {
  if (node.type === 'leaf') return 1;
  return this.countLeaves(node.children[0]) + this.countLeaves(node.children[1]);
}
```

For the same right-heavy tree:
- Top split: 1 left, 3 right → ratio = 1/4 = 0.25 (25% left, 75% right)
- Second split: 1 left, 2 right → ratio = 1/3 = 0.33 (33% of 75% = 25%)
- Third split: 1 left, 1 right → ratio = 0.5 (50% of remaining = 25%)
- Result: all 4 panes = 25% each ✓

## When to Use
- Any binary tree split layout (terminal multiplexers, IDE panels, tiling WMs)
- Auto-arrange / equalize features
- Layout preset generation from user selections
