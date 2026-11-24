# Cap design system

The full design source for Cap, as a Figma file: [open it on Figma Community](https://www.figma.com/community/file/1707045222778979547).

It is free to reuse with credit (CC BY 4.0). Cap's code is MIT licensed (see [LICENSE](LICENSE)). Cap is an independent project and is not made or endorsed by Anthropic. "Claude" is a trademark of Anthropic.

## Get your own copy

1. Open the Community page and duplicate the file to your own drafts.
2. In your copy, publish it as a library for your team (Assets panel, Libraries).
3. Turn the library on in any file where you want to use Cap's components.

The original stays as it is. Your copy is yours to change.

## Use it with Claude

Give your Claude project the link to your copy (Figma's Claude connector can read it) and ask for a screen built from the components. The file is set up for that: components have descriptions, and colors, spacing, radius and type come from variables and text styles, so what Claude builds follows the system.

## What is in the file

| Page | What it holds |
|---|---|
| Start here | What the file is and how to use it |
| Foundations | Color, spacing, radius and type tokens |
| Brand | The Cap logo and its variants |
| Components | Dial, buttons, popover, widget, menu bar item, switches and more |
| Install, Menu bar & Popover, Widget, Settings | Every app screen |
| Prototype | The click-through, from first download to daily use. Open it and press Present (Option+Command+Return) |

## Tokens in code

[`design/tokens.css`](design/tokens.css) holds the same variables as CSS custom properties (`--cap-surface-shell`, `--cap-space-m`, and so on), with light, dark and the seven widget styles. It was checked against the Figma file value by value. Shadows live only in the CSS; Figma draws them as effects.

## Principles

- Show exact numbers, not estimates.
- Terracotta marks only the figure to notice.
- Every state gets a design, including the awkward ones.

## Rules

- Use variables, not hex values.
- Use the text styles.
- Light and dark come from the Color collection's modes. The pinned widget has its own Widget collection with seven modes.
- Spacing and radius come from the Spacing and Radius variables.

## Good to know

- Fonts are Inter, standing in for SF Pro, which has its own licence.
- The install screenshots are from macOS as shipped.
- Some tokens (macOS system chrome colors, for example) exist only to draw mock macOS windows.

## Suggest a change

Figma files do not take pull requests, so:

- For a fix or an idea, [open an issue](https://github.com/bkelson/cap/issues) and say which page and component you mean.
- If you built something on top of the file, publish it to Community and link it in an issue. I would like to see it.
- Please keep the credit line (CC BY 4.0) when you share a copy.
