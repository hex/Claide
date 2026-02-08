// ABOUTME: Copies the visible terminal grid into a flat C-compatible array.
// ABOUTME: Resolves named/indexed colors to RGB using the terminal's color palette.

use alacritty_terminal::grid::Dimensions;
use alacritty_terminal::index::{Column, Line, Point};
use alacritty_terminal::term::cell::{Cell, Flags};
use alacritty_terminal::term::color::Colors;
use alacritty_terminal::term::search::Match;
use alacritty_terminal::term::{Term, TermMode};
use alacritty_terminal::vte::ansi::{Color, CursorShape, NamedColor, Rgb};

use crate::handle::ColorPalette;
use crate::listener::Listener;

/// Per-cell data exposed to Swift via C FFI.
/// Sparse: only non-trivial cells are emitted, with explicit position.
#[repr(C)]
pub struct ClaideCellData {
    pub row: u16,
    pub col: u16,
    pub codepoint: u32,
    pub fg_r: u8,
    pub fg_g: u8,
    pub fg_b: u8,
    pub bg_r: u8,
    pub bg_g: u8,
    pub bg_b: u8,
    pub flags: u16,
}

/// Cursor information exposed to Swift.
#[repr(C)]
pub struct ClaideCursorInfo {
    pub row: u32,
    pub col: u32,
    pub shape: u8, // 0=Block, 1=Underline, 2=Beam, 3=Hidden
    pub visible: bool,
}

/// Complete snapshot of the visible terminal grid.
/// `cells` contains only non-trivial cells (sparse); `cell_count` is the actual length.
#[repr(C)]
pub struct ClaideGridSnapshot {
    pub cells: *mut ClaideCellData,
    pub cell_count: u32,
    pub rows: u32,
    pub cols: u32,
    pub cursor: ClaideCursorInfo,
    pub mode_flags: u32,
    pub padding_bg_r: u8,
    pub padding_bg_g: u8,
    pub padding_bg_b: u8,
}

/// Hexed palette ANSI colors (used as initial values for ColorPalette).
pub const DEFAULT_ANSI: [Rgb; 16] = [
    Rgb { r: 0x00, g: 0x00, b: 0x00 }, // Black
    Rgb { r: 0xff, g: 0x5c, b: 0x57 }, // Red
    Rgb { r: 0x5a, g: 0xf7, b: 0x8e }, // Green
    Rgb { r: 0xf3, g: 0xf9, b: 0x9d }, // Yellow
    Rgb { r: 0x57, g: 0xc7, b: 0xff }, // Blue
    Rgb { r: 0xff, g: 0x6a, b: 0xc1 }, // Magenta
    Rgb { r: 0x9a, g: 0xed, b: 0xfe }, // Cyan
    Rgb { r: 0xf1, g: 0xf1, b: 0xf0 }, // White
    Rgb { r: 0x68, g: 0x68, b: 0x68 }, // Bright Black
    Rgb { r: 0xff, g: 0x5c, b: 0x57 }, // Bright Red
    Rgb { r: 0x5a, g: 0xf7, b: 0x8e }, // Bright Green
    Rgb { r: 0xf3, g: 0xf9, b: 0x9d }, // Bright Yellow
    Rgb { r: 0x57, g: 0xc7, b: 0xff }, // Bright Blue
    Rgb { r: 0xff, g: 0x6a, b: 0xc1 }, // Bright Magenta
    Rgb { r: 0x9a, g: 0xed, b: 0xfe }, // Bright Cyan
    Rgb { r: 0xef, g: 0xf0, b: 0xeb }, // Bright White
];

/// Hexed foreground color (used as initial value for ColorPalette).
pub const DEFAULT_FG: Rgb = Rgb { r: 0xef, g: 0xf0, b: 0xeb };
/// Hexed background color (used as initial value for ColorPalette).
pub const DEFAULT_BG: Rgb = Rgb { r: 0x15, g: 0x17, b: 0x28 };

/// Resolve a Color enum to an RGB triple using the terminal's configured colors
/// and the per-instance palette for fallback values.
fn resolve_color(
    color: &Color,
    colors: &Colors,
    is_foreground: bool,
    palette: &ColorPalette,
) -> Rgb {
    match color {
        Color::Spec(rgb) => *rgb,
        Color::Named(named) => {
            let index = *named as usize;
            if let Some(rgb) = colors[index] {
                rgb
            } else {
                match named {
                    NamedColor::Foreground => colors[NamedColor::Foreground].unwrap_or(palette.fg),
                    NamedColor::Background => colors[NamedColor::Background].unwrap_or(palette.bg),
                    _ if index < 16 => palette.ansi[index],
                    _ => {
                        if is_foreground {
                            palette.fg
                        } else {
                            palette.bg
                        }
                    }
                }
            }
        }
        Color::Indexed(idx) => {
            let index = *idx as usize;
            if let Some(rgb) = colors[index] {
                rgb
            } else if index < 16 {
                palette.ansi[index]
            } else if index < 232 {
                // 6x6x6 color cube
                let idx = index - 16;
                let r = (idx / 36) as u8;
                let g = ((idx / 6) % 6) as u8;
                let b = (idx % 6) as u8;
                Rgb {
                    r: if r > 0 { r * 40 + 55 } else { 0 },
                    g: if g > 0 { g * 40 + 55 } else { 0 },
                    b: if b > 0 { b * 40 + 55 } else { 0 },
                }
            } else {
                // Grayscale ramp
                let v = 8 + (index - 232) as u8 * 10;
                Rgb { r: v, g: v, b: v }
            }
        }
    }
}

/// Map alacritty_terminal cell flags to our C-compatible flag bitfield.
fn map_flags(flags: Flags) -> u16 {
    let mut out: u16 = 0;
    if flags.contains(Flags::BOLD) {
        out |= 0x01;
    }
    if flags.contains(Flags::ITALIC) {
        out |= 0x02;
    }
    if flags.contains(Flags::UNDERLINE) {
        out |= 0x04;
    }
    if flags.contains(Flags::STRIKEOUT) {
        out |= 0x08;
    }
    if flags.contains(Flags::DIM) {
        out |= 0x10;
    }
    if flags.contains(Flags::INVERSE) {
        out |= 0x20;
    }
    if flags.contains(Flags::WIDE_CHAR) {
        out |= 0x40;
    }
    if flags.contains(Flags::WIDE_CHAR_SPACER) {
        out |= 0x80;
    }
    if flags.contains(Flags::HIDDEN) {
        out |= 0x100;
    }
    out
}

/// Check whether a cell's effective background is the terminal default.
/// Accounts for INVERSE flag which swaps fg/bg visually.
fn has_default_bg(cell: &Cell) -> bool {
    let bg_color = if cell.flags.contains(Flags::INVERSE) {
        &cell.fg
    } else {
        &cell.bg
    };
    matches!(bg_color, Color::Named(NamedColor::Background))
}

/// Take a sparse snapshot of the visible terminal grid.
/// Only non-trivial cells (visible content, non-default background, selection,
/// search match, or wide chars) are included. Each cell carries its row/col position.
///
/// The caller must free the returned snapshot with `free_snapshot`.
pub fn take_snapshot(term: &Term<Listener>, palette: &ColorPalette, search_match: Option<&Match>) -> ClaideGridSnapshot {
    let grid = term.grid();
    let rows = grid.screen_lines();
    let cols = grid.columns();
    let display_offset = grid.display_offset();

    let colors = term.colors();
    let mode = *term.mode();

    // Resolve cursor position and shape directly (avoids constructing the full
    // RenderableContent which also builds an unused GridIterator).
    let vi_mode = mode.contains(TermMode::VI);
    let mut cursor_point = if vi_mode { term.vi_mode_cursor.point } else { grid.cursor.point };
    if grid[cursor_point].flags.contains(Flags::WIDE_CHAR_SPACER) {
        cursor_point.column -= 1;
    }
    let cursor_shape = if !vi_mode && !mode.contains(TermMode::SHOW_CURSOR) {
        CursorShape::Hidden
    } else {
        term.cursor_style().shape
    };

    let selection_range = term.selection.as_ref().and_then(|s| s.to_range(term));

    // Sample padding background from bottom-left cell before the sparse loop.
    // This tracks TUI app backgrounds that fill the entire screen.
    let last_line = Line((rows as i32 - 1) - (display_offset as i32));
    let last_row_cell = &grid[last_line][Column(0)];
    let padding_bg = {
        let bg = if last_row_cell.flags.contains(Flags::INVERSE) {
            resolve_color(&last_row_cell.fg, colors, false, palette)
        } else {
            resolve_color(&last_row_cell.bg, colors, false, palette)
        };
        (bg.r, bg.g, bg.b)
    };

    // Pre-allocate for ~20% non-trivial cells (typical shell session).
    let mut cells: Vec<ClaideCellData> = Vec::with_capacity(rows * cols / 4);

    for row_idx in 0..rows {
        let line = Line((row_idx as i32) - (display_offset as i32));
        let grid_row = &grid[line];

        for col_idx in 0..cols {
            let cell: &Cell = &grid_row[Column(col_idx)];
            let point = Point::new(line, Column(col_idx));

            // Determine selection and search state before the trivial check
            let selected = selection_range.as_ref().is_some_and(|r| r.contains(point));
            let is_search_match = search_match.is_some_and(|m| point >= *m.start() && point <= *m.end());

            // A cell is trivial (skip it) if ALL of:
            // - codepoint is space, NUL, or DEL
            // - effective background is the terminal default
            // - not selected
            // - not a search match
            // - not a wide char or wide char spacer
            let cp = cell.c as u32;
            let is_blank = cp == 0x20 || cp == 0x00 || cp == 0x7F;
            let is_wide = cell.flags.intersects(Flags::WIDE_CHAR | Flags::WIDE_CHAR_SPACER);

            if is_blank && has_default_bg(cell) && !selected && !is_search_match && !is_wide {
                continue;
            }

            // Non-trivial cell: resolve colors and emit
            let (mut fg, bg) = if cell.flags.contains(Flags::INVERSE) {
                (
                    resolve_color(&cell.bg, colors, true, palette),
                    resolve_color(&cell.fg, colors, false, palette),
                )
            } else {
                (
                    resolve_color(&cell.fg, colors, true, palette),
                    resolve_color(&cell.bg, colors, false, palette),
                )
            };

            if cell.flags.contains(Flags::DIM) {
                fg.r = fg.r / 2;
                fg.g = fg.g / 2;
                fg.b = fg.b / 2;
            }

            let mut cell_flags = map_flags(cell.flags);

            if selected {
                cell_flags |= 0x200;
            }
            if is_search_match {
                cell_flags |= 0x400;
            }

            cells.push(ClaideCellData {
                row: row_idx as u16,
                col: col_idx as u16,
                codepoint: cp,
                fg_r: fg.r,
                fg_g: fg.g,
                fg_b: fg.b,
                bg_r: bg.r,
                bg_g: bg.g,
                bg_b: bg.b,
                flags: cell_flags,
            });
        }
    }

    let cell_count = cells.len() as u32;
    let cells_ptr = cells.as_mut_ptr();
    std::mem::forget(cells);

    let cursor_shape_id = match cursor_shape {
        CursorShape::Block => 0u8,
        CursorShape::Underline => 1,
        CursorShape::Beam => 2,
        CursorShape::HollowBlock => 4,
        CursorShape::Hidden => 3,
    };

    let cursor_row = (cursor_point.line.0 + display_offset as i32).max(0) as u32;
    let cursor_col = cursor_point.column.0 as u32;

    ClaideGridSnapshot {
        cells: cells_ptr,
        cell_count,
        rows: rows as u32,
        cols: cols as u32,
        cursor: ClaideCursorInfo {
            row: cursor_row,
            col: cursor_col,
            shape: cursor_shape_id,
            visible: cursor_shape_id != 3,
        },
        mode_flags: mode.bits(),
        padding_bg_r: padding_bg.0,
        padding_bg_g: padding_bg.1,
        padding_bg_b: padding_bg.2,
    }
}

/// Free a grid snapshot allocated by `take_snapshot`.
pub unsafe fn free_snapshot(snapshot: *mut ClaideGridSnapshot) {
    if snapshot.is_null() {
        return;
    }
    let snap = &*snapshot;
    let count = snap.cell_count as usize;
    if !snap.cells.is_null() && count > 0 {
        drop(Vec::from_raw_parts(snap.cells, count, count));
    }
    drop(Box::from_raw(snapshot));
}
