# CSS Inline Width Override on Collapse/Expand

**Extracted:** 2026-03-31
**Context:** Any collapsible sidebar/panel with both resize-drag and CSS-class-based collapse

## Problem
When a sidebar supports both drag-to-resize (sets `element.style.width = '240px'`) and
CSS-class-based collapse (`.collapsed { width: 48px }`), the inline style wins due to
CSS specificity. The sidebar stays at the dragged width even when the `.collapsed` class
is applied.

Settings restoration makes it worse: on app load, saved width is applied as inline style,
then collapse class is added, but inline style overrides it.

## Solution
Save and clear inline width when collapsing, restore when expanding:

```typescript
toggleCollapse(): void {
  if (!this.collapsed) {
    // Save current width before collapsing
    this.savedWidth = this.container.offsetWidth;
  }
  this.collapsed = !this.collapsed;
  this.container.classList.toggle('collapsed', this.collapsed);

  if (this.collapsed) {
    this.container.style.width = '';  // Clear so CSS class takes effect
  } else if (this.savedWidth > 0) {
    this.container.style.width = `${this.savedWidth}px`;  // Restore
  }
}
```

Also hide the resize handle when collapsed to prevent re-introducing inline width:
```css
.sidebar.collapsed .resize-handle { display: none; }
```

## When to Use
- Collapsible sidebars with drag-to-resize
- Any element with both inline style dimensions and class-based dimension overrides
- Panels that restore saved dimensions from settings/localStorage
