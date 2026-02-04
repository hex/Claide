// ABOUTME: Copies the visible terminal grid into a flat C-compatible array.
// ABOUTME: Resolves named/indexed colors to RGB using the terminal's color palette.

use alacritty_terminal::grid::Dimensions;
use alacritty_terminal::index::{Column, Line, Point};
use alacritty_terminal::term::cell::{Cell, Flags};
use alacritty_terminal::term::color::Colors;
use alacritty_terminal::term::Term;
use alacritty_terminal::vte::ansi::{Color, NamedColor, Rgb};

use crate::listener::Listener;

/// Per-cell data exposed to Swift via C FFI.
#[repr(C)]
pub struct ClaideCellData {
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
#[repr(C)]
pub struct ClaideGridSnapshot {
    pub cells: *mut ClaideCellData,
    pub rows: u32,
    pub cols: u32,
    pub cursor: ClaideCursorInfo,
    pub mode_flags: u32,
}

/// Default ANSI colors for when the terminal hasn't configured them.
const DEFAULT_ANSI: [Rgb; 16] = [
    Rgb { r: 0x00, g: 0x00, b: 0x00 }, // Black
    Rgb { r: 0xcc, g: 0x00, b: 0x00 }, // Red
    Rgb { r: 0x00, g: 0xcc, b: 0x00 }, // Green
    Rgb { r: 0xcc, g: 0xcc, b: 0x00 }, // Yellow
    Rgb { r: 0x00, g: 0x00, b: 0xcc }, // Blue
    Rgb { r: 0xcc, g: 0x00, b: 0xcc }, // Magenta
    Rgb { r: 0x00, g: 0xcc, b: 0xcc }, // Cyan
    Rgb { r: 0xcc, g: 0xcc, b: 0xcc }, // White
    Rgb { r: 0x55, g: 0x55, b: 0x55 }, // Bright Black
    Rgb { r: 0xff, g: 0x55, b: 0x55 }, // Bright Red
    Rgb { r: 0x55, g: 0xff, b: 0x55 }, // Bright Green
    Rgb { r: 0xff, g: 0xff, b: 0x55 }, // Bright Yellow
    Rgb { r: 0x55, g: 0x55, b: 0xff }, // Bright Blue
    Rgb { r: 0xff, g: 0x55, b: 0xff }, // Bright Magenta
    Rgb { r: 0x55, g: 0xff, b: 0xff }, // Bright Cyan
    Rgb { r: 0xff, g: 0xff, b: 0xff }, // Bright White
];

/// Default foreground color.
const DEFAULT_FG: Rgb = Rgb { r: 0xef, g: 0xf0, b: 0xeb };
/// Default background color.
const DEFAULT_BG: Rgb = Rgb { r: 0x15, g: 0x17, b: 0x28 };

/// Resolve a Color enum to an RGB triple using the terminal's configured colors.
fn resolve_color(color: &Color, colors: &Colors, is_foreground: bool) -> Rgb {
    match color {
        Color::Spec(rgb) => *rgb,
        Color::Named(named) => {
            let index = *named as usize;
            if let Some(rgb) = colors[index] {
                rgb
            } else {
                match named {
                    NamedColor::Foreground => colors[NamedColor::Foreground].unwrap_or(DEFAULT_FG),
                    NamedColor::Background => colors[NamedColor::Background].unwrap_or(DEFAULT_BG),
                    _ if index < 16 => DEFAULT_ANSI[index],
                    _ => {
                        if is_foreground {
                            DEFAULT_FG
                        } else {
                            DEFAULT_BG
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
                DEFAULT_ANSI[index]
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

/// Take a snapshot of the visible terminal grid.
///
/// The caller must free the returned snapshot with `snapshot_free`.
pub fn take_snapshot(term: &Term<Listener>) -> ClaideGridSnapshot {
    let grid = term.grid();
    let rows = grid.screen_lines();
    let cols = grid.columns();
    let display_offset = grid.display_offset();

    let content = term.renderable_content();
    let colors = content.colors;
    let cursor = &content.cursor;
    let mode = content.mode;

    // Resolve selection range for per-cell flagging
    let selection_range = term.selection.as_ref().and_then(|s| s.to_range(term));

    let total_cells = rows * cols;
    let mut cells: Vec<ClaideCellData> = Vec::with_capacity(total_cells);

    for row_idx in 0..rows {
        let line = Line((row_idx as i32) - (display_offset as i32));
        let grid_row = &grid[line];

        for col_idx in 0..cols {
            let cell: &Cell = &grid_row[Column(col_idx)];

            let (mut fg, bg) = if cell.flags.contains(Flags::INVERSE) {
                (
                    resolve_color(&cell.bg, colors, true),
                    resolve_color(&cell.fg, colors, false),
                )
            } else {
                (
                    resolve_color(&cell.fg, colors, true),
                    resolve_color(&cell.bg, colors, false),
                )
            };

            // Apply DIM by halving foreground brightness
            if cell.flags.contains(Flags::DIM) {
                fg.r = fg.r / 2;
                fg.g = fg.g / 2;
                fg.b = fg.b / 2;
            }

            let mut cell_flags = map_flags(cell.flags);

            // Mark selected cells with bit 0x200
            if let Some(ref range) = selection_range {
                let point = Point::new(line, Column(col_idx));
                if range.contains(point) {
                    cell_flags |= 0x200;
                }
            }

            cells.push(ClaideCellData {
                codepoint: cell.c as u32,
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

    let cells_ptr = cells.as_mut_ptr();
    std::mem::forget(cells);

    let cursor_shape = match cursor.shape {
        alacritty_terminal::vte::ansi::CursorShape::Block => 0,
        alacritty_terminal::vte::ansi::CursorShape::Underline => 1,
        alacritty_terminal::vte::ansi::CursorShape::Beam => 2,
        alacritty_terminal::vte::ansi::CursorShape::HollowBlock => 4,
        alacritty_terminal::vte::ansi::CursorShape::Hidden => 3,
    };

    let cursor_row = (cursor.point.line.0 + display_offset as i32).max(0) as u32;
    let cursor_col = cursor.point.column.0 as u32;

    ClaideGridSnapshot {
        cells: cells_ptr,
        rows: rows as u32,
        cols: cols as u32,
        cursor: ClaideCursorInfo {
            row: cursor_row,
            col: cursor_col,
            shape: cursor_shape,
            visible: cursor_shape != 3,
        },
        mode_flags: mode.bits(),
    }
}

/// Free a grid snapshot allocated by `take_snapshot`.
pub unsafe fn free_snapshot(snapshot: *mut ClaideGridSnapshot) {
    if snapshot.is_null() {
        return;
    }
    let snap = &*snapshot;
    let total = (snap.rows as usize) * (snap.cols as usize);
    if !snap.cells.is_null() && total > 0 {
        drop(Vec::from_raw_parts(snap.cells, total, total));
    }
    drop(Box::from_raw(snapshot));
}
