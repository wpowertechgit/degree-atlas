# Degree Atlas design system

Degree Atlas is the course binder that gets passed around the house. The voice is the person who actually took notes and sends you a copy. **here, i took notes.** works on a cover or a share image. **EMAF / HOUSE COPY** is the label on the binder. In the reader, describe actions and status plainly.

## Mark

The handwritten [ΔA](app/assets/brand/degree-atlas.svg) doubles as the project initials and the house letters. Use the [full handwritten wordmark](app/assets/brand/degree-atlas-wordmark.svg) when the name needs to travel with it. Both SVGs contain only ink paths on a transparent background. Leave at least one stroke's worth of clear space around the mark. Use ink on paper or cream on the dark red binder color. Keep the Δ and A legible as separate letters at small sizes.

The app bar uses the full wordmark when space allows and the single mark in narrow windows. The atlas sits on ruled paper with shallow folds, a red margin, and a slim desk edge. The map keeps its domain colors and adds a small landmark emblem to each branch.

The [launcher badge](app/assets/brand/launcher.svg) reverses the ΔA to cream on binder red. Regenerate the Windows ICO and Android icons with `python scripts/build_launcher_icons.py` from the repo root. The script needs Inkscape on PATH and Pillow. It uses the handwritten SVG as the source for both platforms.

## Color and type

The Flutter source for the reader tokens is [HouseStyle](app/lib/house_style.dart).

| Token | Value | Role |
| --- | --- | --- |
| Paper | **#FFFBF0** | Notebook sheet |
| Desk | **#EFE7DD** | Space around the sheet |
| Ink | **#211D1B** | Mark, titles and reading text |
| Graphite | **#675951** | Supporting text and status |
| Binder | **#732F36** | House label, underline and close control |
| Pen | **#2B5078** | Book sketches and links |
| Ruling | **#EBEEF0** | Horizontal paper lines |
| Margin | **#E6C7C7** | Gutter line and section dividers |
| Page edge | **#E8DCD0** | Bottom sheets and hole edges |

Use Kalam Bold for the course title and note headings. Use the existing Noto Sans body for notes, controls and form fields, and keep formulas in the math renderer. The small house label uses monospaced type. Keep reading text at 15 logical pixels with a line height of 1.55. The title uses 40 logical pixels on wide pages and 31 on compact pages, with system text scaling applied.

## Reader components

| Component | Behavior |
| --- | --- |
| Sheet | Center the paper, cap it at 920 logical pixels, and use the 8 pixel spacing unit for gutters and gaps. Show faint 28 pixel ruling and binder holes beside the margin line. Use a narrower gutter on small windows. |
| Title | Lead with the course name and a short ink underline. Wrap long names and keep the title available as a screen reader heading. |
| Level tabs | Label tabs L0 through L3. Give the selected tab a tinted fill and reserve the darker text treatment for levels with notes. Keep unwritten levels selectable so their status and available actions are discoverable. |
| Notes | Use normal typeset paragraphs, selectable Markdown and inline figures. Put the existing read and edit actions above the notes. |
| Sketches | Keep the open book beside the title on wide pages. Put small vector drawings in a dedicated gutter beside longer notes and below the notes on compact pages. Give the drawings room for their whole movement so they stay clear of text, figures and controls. |

## Motion

Atlas idle scenes play in pairs, one in each margin. Each scene keeps its own timing, with a short stagger between starts. Panning, zooming and typing defer the pair, and reduced motion keeps the resting artwork visible.

Play the entrance once when a course notebook opens. Write the title from left to right, one line at a time, then lower the notes into position and trace the book. The sequence lasts about 1.55 seconds. Changing a level keeps the notebook open.

While the notebook is open, let the pencil hop, the paper plane loop, or the ink blot pop into a star. Use soft landings, quick shape changes, and a few pen scratches for movement. Each burst lasts about 2.5 seconds with several seconds of stillness before the next one. The drawings scroll with the paper. With reduced motion enabled, show the finished page and the resting drawings immediately.

Use the mark and ruled paper for repo and share art. When a sketch needs actual words or equations, take them from a real set of notes so the cover looks like someone used it.
